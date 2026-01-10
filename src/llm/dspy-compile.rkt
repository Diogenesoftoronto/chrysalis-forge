#lang racket
(provide compile! bootstrap-fewshot default-instruction-mutations)
(require "dspy-core.rkt" "pricing-model.rkt" "../core/optimizer-meta.rkt" racket/list racket/string)

(define (bootstrap-fewshot trainset #:k [k 3])
  (take (shuffle trainset) (min k (length trainset))))

(define (default-instruction-mutations base)
  (list (string-trim base) (string-append base "\nBe concise.")
        (string-append base "\nThink step-by-step.") (string-append base "\nOutput STRICT JSON.")))

(define (median lon)
  (if (null? lon) 0
      (let ([sorted (sort lon <)])
        (list-ref sorted (quotient (length sorted) 2)))))

;; Extract continuous phenotype from a RunResult
(define (extract-phenotype rr score)
  (define meta (RunResult-meta rr))
  (define model (hash-ref meta 'model "unknown"))
  (define p-tokens (hash-ref meta 'prompt_tokens 0))
  (define c-tokens (hash-ref meta 'completion_tokens 0))
  (define cost (calculate-cost model p-tokens c-tokens))
  (define lat (hash-ref meta 'elapsed_ms 0))
  (define total-tokens (+ p-tokens c-tokens))
  (Phenotype score lat cost total-tokens))

;; Map phenotypic bins: (cost-bin, latency-bin, usage-bin) relative to thresholds
(define (get-phenotype-key rr [t-cost 0.0] [t-lat 0.0] [t-usage 0.0])
  (define meta (RunResult-meta rr))
  (define model (hash-ref meta 'model "unknown"))
  (define p-tokens (hash-ref meta 'prompt_tokens 0))
  (define c-tokens (hash-ref meta 'completion_tokens 0))
  (define cost (calculate-cost model p-tokens c-tokens))
  (define lat (hash-ref meta 'elapsed_ms 0))
  (define total-tokens (+ p-tokens c-tokens))
  
  (list (if (< cost t-cost) 'cheap 'premium)
        (if (< lat t-lat) 'fast 'slow)
        (if (< total-tokens t-usage) 'compact 'verbose)))

(define (compile! m ctx trainset send! 
                 #:k-demos [k 3] 
                 #:n-inst [n 5] 
                 #:iters [iters 3]
                 #:use-meta-optimizer? [use-meta? #t])
                 
  (define demos (bootstrap-fewshot trainset #:k k))
  (define m0 (module-set-demos m demos))
  
  (define archive (make-hash))
  (define point-cloud '()) ;; List of (cons Phenotype Module)
  
  (define thresholds (hash 'cost 0.0 'lat 0.0 'usage 0.0))

  (define (evaluate-module mod)
    (define results (for/list ([ex trainset]) (run-module mod ctx (hash-ref ex 'inputs) send!)))
    (define scores (for/list ([res results] [ex trainset]) (score-result (hash-ref ex 'expected) res)))
    (define avg-score (if (null? scores) 0 (/ (apply + scores) (length scores))))
    (define p-key 
      (if (null? results) 
          '(cheap fast compact)
          (get-phenotype-key (car results) 
                             (hash-ref thresholds 'cost)
                             (hash-ref thresholds 'lat)
                             (hash-ref thresholds 'usage))))
    (values avg-score p-key results))

  (define (update-archive! mod score p-key res-list)
    (define existing (hash-ref archive p-key #f))
    (when (or (not existing) (> score (car existing)))
      (log-info "New elite for bin ~a: ~a" p-key score)
      (hash-set! archive p-key (cons score mod)))
    ;; Always add to point cloud for geometric search
    (unless (null? res-list)
      (define pheno (extract-phenotype (car res-list) score))
      (set! point-cloud (cons (cons pheno mod) point-cloud))))

  ;; 1. Initialization
  (log-info "Initializing population and establishing relative baselines...")
  (define seeds (default-instruction-mutations (Module-instructions m0)))
  
  (define seed-results
    (for/list ([inst seeds])
      (define mod (module-set-instructions m0 inst))
      (let-values ([(score p-key res-list) (evaluate-module mod)])
        (list mod score p-key res-list))))

  ;; Calculate relative thresholds
  (define all-meta (flatten (map (λ (x) (map RunResult-meta (fourth x))) seed-results)))
  (unless (null? all-meta)
    (define costs (for/list ([m all-meta]) (calculate-cost (hash-ref m 'model "unknown") (hash-ref m 'prompt_tokens 0) (hash-ref m 'completion_tokens 0))))
    (define lats (for/list ([m all-meta]) (hash-ref m 'elapsed_ms 0)))
    (define usages (for/list ([m all-meta]) (+ (hash-ref m 'prompt_tokens 0) (hash-ref m 'completion_tokens 0))))
    
    (set! thresholds (hash 'cost (median costs)
                           'lat (median lats)
                           'usage (median usages)))
    (log-info "Established relative thresholds from median: ~v" thresholds))

  ;; Re-bin seeds with new thresholds and populate archive + point cloud
  (for ([s seed-results])
    (define mod (first s))
    (define score (second s))
    (define res-list (fourth s))
    (define p-key (get-phenotype-key (car res-list) (hash-ref thresholds 'cost) (hash-ref thresholds 'lat) (hash-ref thresholds 'usage)))
    (update-archive! mod score p-key res-list))

  ;; 2. Evolutionary Loop (MAP-Elites)
  (for ([i (range iters)] #:when use-meta?)
    (log-info "Generation ~a archive size: ~a point-cloud size: ~a" i (hash-count archive) (length point-cloud))
    (define elite-keys (hash-keys archive))
    (when (not (null? elite-keys))
      (define parent-key (list-ref elite-keys (random (length elite-keys))))
      (define parent-mod (cdr (hash-ref archive parent-key)))
      
      (for ([j (range n)])
        (let-values ([(child-mod thought) (meta-optimize-module parent-mod ctx trainset send!)])
          (let-values ([(score p-key res-list) (evaluate-module child-mod)])
            (update-archive! child-mod score p-key res-list))))))

  ;; Return a ModuleArchive
  (define best-key (argmax (λ (k) (car (hash-ref archive k))) (hash-keys archive)))
  (log-info "Optimization complete. Archive size: ~a Point cloud size: ~a" (hash-count archive) (length point-cloud))
  (ModuleArchive (Module-id m0) (Module-sig m0) archive point-cloud best-key))