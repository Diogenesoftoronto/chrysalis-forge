#lang racket/base
(provide evolve-agent!
         select-next-parent
         run-candidate-eval!)

(require "../stores/agent-archive.rkt"
         "../stores/eval-store.rkt"
         "../llm/openai-client.rkt"
         "../utils/debug.rkt"
         "../core/runtime.rkt"
         json
         racket/file
         racket/list
         racket/string
         racket/date)

;; ============================================================================
;; AGENT EVOLUTION - HyperAgents-style evolutionary loop
;; ============================================================================

;; Mutate a parent variant to create a new candidate
(define (mutate-variant parent type feedback [model (evolution-model-param)])
  (define sender (make-openai-sender #:model model))
  (define content (AgentVariant-content parent))
  
  (define prompt
    (format "You are an Agent Evolution Meta-Agent. 
Your goal is to improve an agent component based on feedback.
Component Type: ~a
Current Content: ~a
Feedback: ~a

Return JSON with 'new_content' field.
If it's a prompt, return the rewritten prompt.
If it's a workflow, return the updated workflow JSON.
If it's a tool-profile, return the list of allowed tools.

Output STRICT JSON only." type content feedback))

  (define-values (ok? res usage) (sender prompt))
  (if ok?
      (let* ([js (string->jsexpr res)]
             [new-content (hash-ref js 'new_content)]
             [id (format "var-~a-~a" type (current-seconds))])
        (AgentVariant id (AgentVariant-id parent) type new-content (hash) 
                      (AgentVariant-task-family parent) 
                      (hash 'timestamp (current-seconds) 'model model)
                      #t))
      #f))

;; Select the next parent from the archive (non-greedy)
(define (select-next-parent archive task-family)
  (define variants (AgentArchive-variants archive))
  (define eligible (filter (λ (v) (and (equal? (AgentVariant-task-family v) task-family)
                                       (AgentVariant-viable v)))
                           variants))
  
  (if (null? eligible)
      #f
      ;; Selection strategy: mix of best and exploration
      (let* ([sorted (sort eligible > 
                           #:key (λ (v) (hash-ref (AgentVariant-eval-summary v) 'success_rate 0.0)))]
             [best (take sorted (min 3 (length sorted)))]
             [recent (take eligible (min 3 (length eligible)))]
             [candidates (remove-duplicates (append best recent))])
        (list-ref candidates (random (length candidates))))))

;; Run evaluation for a candidate
;; In a real system, this would execute a suite of tasks.
;; For now, we'll provide a mock runner that takes a 'benchmark' function.
(define (run-candidate-eval! candidate benchmark-fn #:stage [stage "smoke"])
  (log-debug 1 'evolve "Starting evaluation for candidate ~a (stage: ~a)" (AgentVariant-id candidate) stage)
  
  (define-values (success-rate avg-duration) (benchmark-fn candidate stage))
  
  (log-debug 1 'evolve "Evaluation complete: success_rate=~a, avg_duration=~a" success-rate avg-duration)
  
  (struct-copy AgentVariant candidate
               [eval-summary (hash 'success_rate success-rate
                                   'avg_duration avg-duration
                                   'last_eval_ts (current-seconds)
                                   'stage stage)]
               [viable (>= success-rate 0.5)]))

;; Main evolution loop entry point
(define (evolve-agent! type task-family feedback benchmark-fn #:iterations [iterations 1] #:model [model (evolution-model-param)])
  (define archive (load-agent-archive type))
  
  (let loop ([current-iter 0]
             [current-archive archive])
    (if (>= current-iter iterations)
        (begin
          (save-agent-archive! type current-archive)
          "Evolution sequence complete.")
        (let* ([parent (select-next-parent current-archive task-family)]
               [parent (or parent 
                           ;; Fallback to a default variant if none exists
                           (AgentVariant "default" #f type "" (hash) task-family (hash) #t))]
               [candidate (mutate-variant parent type feedback model)])
          
          (if candidate
              (let* ([evaluated (run-candidate-eval! candidate benchmark-fn #:stage "smoke")]
                     [final-evaluated 
                      (if (AgentVariant-viable evaluated)
                          (run-candidate-eval! evaluated benchmark-fn #:stage "full")
                          evaluated)]
                     [new-archive (record-variant! current-archive final-evaluated)])
                (loop (add1 current-iter) new-archive))
              (begin
                (log-debug 1 'evolve "Mutation failed, skipping iteration")
                (loop (add1 current-iter) current-archive)))))))
