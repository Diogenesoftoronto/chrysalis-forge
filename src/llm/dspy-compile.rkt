#lang racket
(provide compile! bootstrap-fewshot default-instruction-mutations)
(require "dspy-core.rkt" "../core/optimizer-meta.rkt" racket/list racket/string)

(define (bootstrap-fewshot trainset #:k [k 3])
  (take (shuffle trainset) (min k (length trainset))))

(define (default-instruction-mutations base)
  (list (string-trim base) (string-append base "\nBe concise.")
        (string-append base "\nThink step-by-step.") (string-append base "\nOutput STRICT JSON.")))

(define (score-result expected actual) (if (equal? expected actual) 10.0 0.0))

(define (compile! m ctx trainset send! #:k-demos [k 3] #:n-inst [n 5] #:use-meta-optimizer? [use-meta? #f])
  (define demos (bootstrap-fewshot trainset #:k k))
  (define m0 (module-set-demos m demos))
  (define candidates 
    (if use-meta?
        (let loop ([cands '()] [i 0])
          (if (= i n) cands
              (let-values ([(m-new thought) (meta-optimize-module m0 ctx trainset send!)])
                (loop (cons (Module-instructions m-new) cands) (add1 i)))))
        (default-instruction-mutations (Module-instructions m0))))
  
  (define scored
    (for/list ([inst candidates])
      (define mX (module-set-instructions m0 inst))
      (define scores
        (for/list ([ex trainset])
          (define rr (run-module mX ctx (hash-ref ex 'inputs) send!))
          (score-result (hash-ref ex 'expected) (RunResult-outputs rr))))
      (cons mX (if (null? scores) 0 (/ (apply + scores) (length scores))))))
  (car (argmax cdr scored)))