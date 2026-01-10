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
  
  ;; Start with zero thresholds - this ensures the initial seed evaluation 
  ;; doesn't rely on arbitrary defaults. Everything will be 'premium/'slow/'verbose
  ;; until the relative medians are calculated.
  (define thresholds (hash 'cost 0.0 'lat 0.0 'usage 0.0))

  (define (evaluate-module mod)
    (define results (for/list ([ex trainset]) (run-module mod ctx (hash-ref ex 'inputs) send!)))
    (define scores (for/list ([res results] [ex trainset]) (score-result (hash-ref ex 'expected) res)))
    (define avg-score (if (null? scores) 0 (/ (apply + scores) (length scores))))
    (define p-key 
      (if (null? results) 
          '(cheap fast compact) ;; Theoretical best if no results
          (get-phenotype-key (car results) 
                             (hash-ref thresholds 'cost)
                             (hash-ref thresholds 'lat)
                             (hash-ref thresholds 'usage))))
    (values avg-score p-key results))

  (define (update-archive! mod score p-key)
    (define existing (hash-ref archive p-key #f))
    (when (or (not existing) (> score (car existing)))
      (log-info "New elite for bin ~a: ~a" p-key score)
      (hash-set! archive p-key (cons score mod))))

  ;; 1. Initialization: Evaluation of seeds to establish relative baselines
  (log-info "Initializing population and establishing relative baselines...")
  (define seeds (default-instruction-mutations (Module-instructions m0)))
  
  (define seed-results
    (for/list ([inst seeds])
      (define mod (module-set-instructions m0 inst))
      (let-values ([(score p-key res-list) (evaluate-module mod)])
        (list mod score res-list))))

  ;; Calculate relative thresholds strictly from observed data (no floors)
  (define all-meta (flatten (map (λ (x) (map RunResult-meta (third x))) seed-results)))
  (unless (null? all-meta)
    (define costs (for/list ([m all-meta]) (calculate-cost (hash-ref m 'model "unknown") (hash-ref m 'prompt_tokens 0) (hash-ref m 'completion_tokens 0))))
    (define lats (for/list ([m all-meta]) (hash-ref m 'elapsed_ms 0)))
    (define usages (for/list ([m all-meta]) (+ (hash-ref m 'prompt_tokens 0) (hash-ref m 'completion_tokens 0))))
    
    (set! thresholds (hash 'cost (median costs)
                           'lat (median lats)
                           'usage (median usages)))
    (log-info "Established relative thresholds from median: ~v" thresholds))

  ;; Re-bin and update archive with seeds using the newly established relative thresholds
  (for ([s seed-results])
    (define mod (first s))
    (define score (second s))
    (define res-list (third s))
    (define p-key (get-phenotype-key (car res-list) (hash-ref thresholds 'cost) (hash-ref thresholds 'lat) (hash-ref thresholds 'usage)))
    (update-archive! mod score p-key))

  ;; 2. Evolutionary Loop (MAP-Elites)
  (for ([i (range iters)] #:when use-meta?)
    (log-info "Generation ~a archive size: ~a" i (hash-count archive))
    (define elite-keys (hash-keys archive))
    (when (not (null? elite-keys))
      (define parent-key (list-ref elite-keys (random (length elite-keys))))
      (define parent-mod (cdr (hash-ref archive parent-key)))
      
      (for ([j (range n)])
        (let-values ([(child-mod thought) (meta-optimize-module parent-mod ctx trainset send!)])
          (let-values ([(score p-key res-list) (evaluate-module child-mod)])
            (update-archive! child-mod score p-key))))))

  ;; Return a ModuleArchive for runtime selection
  (define best-key (argmax (λ (k) (car (hash-ref archive k))) (hash-keys archive)))
  (log-info "Optimization complete. Archive size: ~a" (hash-count archive))
  (ModuleArchive (Module-id m0) (Module-sig m0) archive best-key))