#lang racket
(provide compile! bootstrap-fewshot default-instruction-mutations)
(require "dspy-core.rkt" "pricing-model.rkt" "../core/optimizer-meta.rkt" racket/list racket/string)

(define (bootstrap-fewshot trainset #:k [k 3])
  (take (shuffle trainset) (min k (length trainset))))

(define (default-instruction-mutations base)
  (list (string-trim base) (string-append base "\nBe concise.")
        (string-append base "\nThink step-by-step.") (string-append base "\nOutput STRICT JSON.")))

;; Map phenotypic bins: (cost-bin, latency-bin, usage-bin)
(define (get-phenotype-key rr)
  (define meta (RunResult-meta rr))
  (define model (hash-ref meta 'model "unknown"))
  (define p-tokens (hash-ref meta 'prompt_tokens 0))
  (define c-tokens (hash-ref meta 'completion_tokens 0))
  (define cost (calculate-cost model p-tokens c-tokens))
  (define lat (hash-ref meta 'elapsed_ms 0))
  (define total-tokens (+ p-tokens c-tokens))
  
  (list (if (< cost 0.0005) 'cheap 'premium)
        (if (< lat 3000) 'fast 'slow)
        (if (< total-tokens 500) 'compact 'verbose)))

(define (compile! m ctx trainset send! 
                 #:k-demos [k 3] 
                 #:n-inst [n 5] 
                 #:iters [iters 3]
                 #:use-meta-optimizer? [use-meta? #t])
                 
  (define demos (bootstrap-fewshot trainset #:k k))
  (define m0 (module-set-demos m demos))
  
  ;; The Archive: maps (cost latency usage) -> (cons score module)
  (define archive (make-hash))
  
  (define (evaluate-module mod)
    (define results (for/list ([ex trainset]) (run-module mod ctx (hash-ref ex 'inputs) send!)))
    (define scores (for/list ([res results] [ex trainset]) (score-result (hash-ref ex 'expected) res)))
    (define avg-score (if (null? scores) 0 (/ (apply + scores) (length scores))))
    (define p-key (if (null? results) '(cheap fast compact) (get-phenotype-key (car results))))
    (values avg-score p-key))

  (define (update-archive! mod score p-key)
    (define existing (hash-ref archive p-key #f))
    (when (or (not existing) (> score (car existing)))
      (log-info "New elite for bin ~a: ~a" p-key score)
      (hash-set! archive p-key (cons score mod))))

  ;; 1. Initialization: Seed the archive
  (log-info "Initializing population...")
  (define seeds (default-instruction-mutations (Module-instructions m0)))
  (for ([inst seeds])
    (define mod (module-set-instructions m0 inst))
    (let-values ([(score p-key) (evaluate-module mod)])
      (update-archive! mod score p-key)))

  ;; 2. Evolutionary Loop (MAP-Elites)
  (for ([i (range iters)] #:when use-meta?)
    (log-info "Generation ~a archive size: ~a" i (hash-count archive))
    ;; Mutation: Pick a random elite to improve
    (define elite-keys (hash-keys archive))
    (when (not (null? elite-keys))
      (define parent-key (list-ref elite-keys (random (length elite-keys))))
      (define parent-mod (cdr (hash-ref archive parent-key)))
      
      ;; Call meta-optimizer to mutate the elite based on its specific failures
      (for ([j (range n)])
        (let-values ([(child-mod thought) (meta-optimize-module parent-mod ctx trainset send!)])
          (let-values ([(score p-key) (evaluate-module child-mod)])
            (update-archive! child-mod score p-key))))))

  ;; Return a ModuleArchive for runtime selection
  (define best-key (argmax (λ (k) (car (hash-ref archive k))) (hash-keys archive)))
  (log-info "Optimization complete. Archive size: ~a" (hash-count archive))
  (ModuleArchive (Module-id m0) (Module-sig m0) archive best-key))