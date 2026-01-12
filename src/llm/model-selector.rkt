#lang racket/base
(provide ModelSelectionRequest ModelSelectionRequest?
         ModelSelectionRequest-task-type ModelSelectionRequest-profile
         ModelSelectionRequest-priority ModelSelectionRequest-phase
         ModelSelectionRequest-context-needed ModelSelectionRequest-constraints
         exploration-rate
         score-model-static score-model-priority score-model-learned
         compute-model-score
         select-model select-model-for-phase select-model-for-subtask
         select-decomposition-model select-execution-model
         interpret-priority
         select-model-chain)

(require "model-registry.rkt"
         "dspy-core.rkt"
         racket/list
         racket/match
         racket/math
         racket/hash)

(struct ModelSelectionRequest
  (task-type profile priority phase context-needed constraints)
  #:transparent)

(define exploration-rate (make-parameter 0.1))

(define (score-model-static caps request)
  (define task-type (ModelSelectionRequest-task-type request))
  (define phase (ModelSelectionRequest-phase request))
  (define profile (ModelSelectionRequest-profile request))
  (define best-for (ModelCapabilities-best-for caps))
  
  (define task-match-score
    (if (member task-type best-for)
        1.0
        (if (member "general" best-for) 0.5 0.3)))
  
  (define phase-score
    (case phase
      [(decompose)
       (* 0.7 (ModelCapabilities-speed caps))]
      [(execute)
       (* 0.5 (+ (ModelCapabilities-reasoning caps)
                 (ModelCapabilities-coding caps)))]
      [else 0.5]))
  
  (define profile-score
    (case profile
      [(editor)
       (ModelCapabilities-coding caps)]
      [(researcher)
       (ModelCapabilities-reasoning caps)]
      [(vcs)
       (* 0.5 (+ (ModelCapabilities-speed caps) (ModelCapabilities-coding caps)))]
      [(all)
       (* 0.33 (+ (ModelCapabilities-reasoning caps)
                  (ModelCapabilities-coding caps)
                  (ModelCapabilities-speed caps)))]
      [else 0.5]))
  
  (define weights '(0.4 0.3 0.3))
  (+ (* (first weights) task-match-score)
     (* (second weights) phase-score)
     (* (third weights) profile-score)))

(define (score-model-priority caps priority)
  (define cost-tier (ModelCapabilities-cost-tier caps))
  (define speed (ModelCapabilities-speed caps))
  (define reasoning (ModelCapabilities-reasoning caps))
  (define coding (ModelCapabilities-coding caps))
  
  (define tier-score
    (case cost-tier
      [(cheap) 1.0]
      [(medium) 0.6]
      [(expensive) 0.3]
      [(premium) 0.1]
      [else 0.5]))
  
  (define prio-sym
    (if (symbol? priority)
        priority
        (interpret-priority priority)))
  
  (case prio-sym
    [(cheap)
     (* 0.5 (+ tier-score speed))]
    [(fast)
     speed]
    [(best)
     (* 0.5 (+ reasoning coding))]
    [else
     (* 0.33 (+ tier-score speed (* 0.5 (+ reasoning coding))))]))

(define (score-model-learned stats task-type profile)
  (cond
    [(not stats) 0.5]
    [else
     (define total-calls (ModelStats-total-calls stats))
     (when (= total-calls 0)
       (return 0.5))
     
     (define global-success-rate
       (/ (ModelStats-success-calls stats) total-calls))
     
     (define task-entry (hash-ref (ModelStats-by-task-type stats) task-type #f))
     (define task-success-rate
       (if (and task-entry (> (hash-ref task-entry 'calls 0) 0))
           (/ (hash-ref task-entry 'successes 0) (hash-ref task-entry 'calls 0))
           #f))
     
     (define avg-latency-ms (/ (ModelStats-total-ms stats) total-calls))
     (define latency-score
       (cond
         [(< avg-latency-ms 1000) 1.0]
         [(< avg-latency-ms 3000) 0.8]
         [(< avg-latency-ms 5000) 0.6]
         [(< avg-latency-ms 10000) 0.4]
         [else 0.2]))
     
     (define success-score
       (if task-success-rate
           (* 0.5 (+ global-success-rate task-success-rate))
           global-success-rate))
     
     (* 0.5 (+ success-score latency-score))]))

(define-syntax-rule (return v)
  v)

(define (compute-model-score record request)
  (define caps (ModelRecord-caps record))
  (define stats (ModelRecord-stats record))
  (define task-type (ModelSelectionRequest-task-type request))
  (define profile (ModelSelectionRequest-profile request))
  (define priority (ModelSelectionRequest-priority request))
  (define context-needed (ModelSelectionRequest-context-needed request))
  (define constraints (ModelSelectionRequest-constraints request))
  
  (when (> context-needed (ModelCapabilities-max-context caps))
    (return (values -inf.0 #f)))
  
  (when (and (hash-ref constraints 'require-tools? #f)
             (not (ModelCapabilities-supports-tools? caps)))
    (return (values -inf.0 #f)))
  
  (when (and (hash-ref constraints 'require-vision? #f)
             (not (ModelCapabilities-supports-vision? caps)))
    (return (values -inf.0 #f)))
  
  (define excluded (hash-ref constraints 'exclude-models '()))
  (when (member (ModelCapabilities-id caps) excluded)
    (return (values -inf.0 #f)))
  
  (define total-calls (if stats (ModelStats-total-calls stats) 0))
  
  (define-values (w-static w-priority w-learned)
    (if (> total-calls 50)
        (values 0.25 0.25 0.5)
        (values 0.5 0.3 0.2)))
  
  (define static-score (score-model-static caps request))
  (define priority-score (score-model-priority caps priority))
  (define learned-score (score-model-learned stats task-type profile))
  
  (define final-score
    (+ (* w-static static-score)
       (* w-priority priority-score)
       (* w-learned learned-score)))
  
  (values final-score #t))

(define (select-model request)
  (define available (list-available-models))
  (when (null? available)
    (error 'select-model "No available models in registry"))
  
  (define scored
    (filter-map
     (λ (rec)
       (define-values (score feasible?) (compute-model-score rec request))
       (and feasible? (cons score rec)))
     available))
  
  (when (null? scored)
    (error 'select-model "No feasible models for request"))
  
  (define sorted (sort scored > #:key car))
  
  (define should-explore?
    (and (> (length sorted) 1)
         (< (random) (exploration-rate))))
  
  (define selected-rec
    (if should-explore?
        (let ()
          (define cheap-models
            (filter (λ (p)
                      (eq? (ModelCapabilities-cost-tier
                            (ModelRecord-caps (cdr p)))
                           'cheap))
                    sorted))
          (define less-used
            (filter (λ (p)
                      (define stats (ModelRecord-stats (cdr p)))
                      (or (not stats)
                          (< (ModelStats-total-calls stats) 10)))
                    sorted))
          (define explore-pool (if (null? cheap-models) less-used cheap-models))
          (if (null? explore-pool)
              (cdr (first sorted))
              (cdr (list-ref explore-pool (random (length explore-pool))))))
        (cdr (first sorted))))
  
  (ModelCapabilities-id (ModelRecord-caps selected-rec)))

(define (select-model-for-phase phase priority #:context [ctx 80000])
  (select-model
   (ModelSelectionRequest
    "general"
    'all
    priority
    phase
    ctx
    (hash))))

(define (select-model-for-subtask task-type profile priority
                                   #:phase [phase 'execute]
                                   #:context [ctx 80000]
                                   #:require-tools? [tools? #f])
  (select-model
   (ModelSelectionRequest
    task-type
    profile
    priority
    phase
    ctx
    (hash 'require-tools? tools?))))

(define (select-decomposition-model priority)
  (select-model-for-phase 'decompose priority #:context 40000))

(define (select-execution-model task-type profile priority)
  (select-model-for-subtask task-type profile priority #:phase 'execute))

(define (interpret-priority p)
  (cond
    [(symbol? p) p]
    [(not (string? p)) 'best]
    [else
     (define lower (string-downcase p))
     (cond
       [(or (string-contains? lower "fast")
            (string-contains? lower "quick")
            (string-contains? lower "speed")
            (string-contains? lower "urgent"))
        'fast]
       [(or (string-contains? lower "cheap")
            (string-contains? lower "budget")
            (string-contains? lower "cost")
            (string-contains? lower "save")
            (string-contains? lower "economy"))
        'cheap]
       [(or (string-contains? lower "best")
            (string-contains? lower "quality")
            (string-contains? lower "accurate")
            (string-contains? lower "thorough")
            (string-contains? lower "premium"))
        'best]
       [else 'best])]))

(define (string-contains? str sub)
  (regexp-match? (regexp-quote sub) str))

(define (select-model-chain task-type profile priority)
  (values (select-decomposition-model 'fast)
          (select-execution-model task-type profile priority)))
