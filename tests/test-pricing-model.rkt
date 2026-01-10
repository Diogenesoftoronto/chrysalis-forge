#lang racket/base
(require rackunit
         "../pricing-model.rkt")

(provide pricing-model-tests)

(define pricing-model-tests
  (test-suite
   "pricing-model tests"
   
   (test-case
    "calculate-cost"
    ;; gpt-4o: $5 input, $15 output per 1M
    (check-equal? (calculate-cost "gpt-4o" 1000000 0) 5.0)
    (check-equal? (calculate-cost "gpt-4o" 0 1000000) 15.0)
    (check-equal? (calculate-cost "gpt-4o" 1000000 1000000) 20.0)
    
    ;; gpt-4o-mini: $0.15 input, $0.6 output per 1M
    (check-equal? (calculate-cost "gpt-4o-mini" 1000000 0) 0.15)
    
    ;; Unknown model
    (check-equal? (calculate-cost "unknown-model" 1000 1000) 0.0))))

(module+ test
  (require rackunit/text-ui)
  (run-tests pricing-model-tests))
