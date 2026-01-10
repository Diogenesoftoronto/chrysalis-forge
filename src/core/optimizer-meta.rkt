#lang racket
(provide (all-defined-out))
(require "../llm/dspy-core.rkt" "../llm/openai-client.rkt" json)

(define OptSig (signature Opt (in [inst string?] [fails string?]) (out [thought string?] [new_inst string?])))
(define (make-meta-optimizer) (ChainOfThought OptSig #:instructions "Fix failing examples. Return JSON." #:params (hash 'temperature 0.7)))

(define (meta-optimize-module target ctx trainset send!)
  (define failures (filter (λ (ex) (< (score-result (hash-ref ex 'expected) (RunResult-outputs (run-module target ctx (hash-ref ex 'inputs) send!))) 10)) trainset))
  (if (null? failures) (values target "No failures")
      (let ([rr (run-module (make-meta-optimizer) ctx (hash 'inst (Module-instructions target) 'fails (jsexpr->string (take failures (min 3 (length failures))))) send!)])
        (if (RunResult-ok? rr) (values (module-set-instructions target (hash-ref (RunResult-outputs rr) 'new_inst)) "Optimized") (values target "Failed")))))
(define (score-result e a) (if (equal? e a) 10.0 0.0))