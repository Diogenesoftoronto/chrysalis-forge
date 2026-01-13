#lang racket/base
(require rackunit
         "../src/llm/pricing-model.rkt")

(provide pricing-model-tests)

(define pricing-model-tests
  (test-suite
   "pricing-model tests"
   
   (test-case
    "calculate-cost with default pricing"
    ;; Reset to defaults to avoid network fetch interference
    (reset-pricing!)
    ;; gpt-4o: $2.50 input, $10.00 output per 1M tokens
    (check-equal? (calculate-cost "gpt-4o" 1000000 0) 2.5)
    (check-equal? (calculate-cost "gpt-4o" 0 1000000) 10.0)
    (check-equal? (calculate-cost "gpt-4o" 1000000 1000000) 12.5)
    
    ;; gpt-4o-mini: $0.15 input, $0.60 output per 1M tokens
    (check-equal? (calculate-cost "gpt-4o-mini" 1000000 0) 0.15)
    (check-equal? (calculate-cost "gpt-4o-mini" 0 1000000) 0.6)
    
    ;; gpt-5.2: $5.00 input, $15.00 output per 1M tokens
    (check-equal? (calculate-cost "gpt-5.2" 1000000 0) 5.0)
    (check-equal? (calculate-cost "gpt-5.2" 0 1000000) 15.0)
    
    ;; o1-preview: $15.00 input, $60.00 output per 1M tokens
    (check-equal? (calculate-cost "o1-preview" 500000 500000) (+ 7.5 30.0))
    
    ;; Unknown model returns 0
    (check-equal? (calculate-cost "unknown-model" 1000 1000) 0.0))
   
   (test-case
    "fetch-usage-stats requires API key"
    ;; Should raise error when no API key is set
    (check-exn exn:fail:user?
               (lambda ()
                 (parameterize ([current-environment-variables
                                 (make-environment-variables)])
                   (fetch-usage-stats)))))
   
   (test-case
    "update-pricing! fetches from network"
    ;; Clear pricing and fetch fresh
    (clear-pricing!)
    (update-pricing!)
    ;; Should have fetched at least some models
    (check-true (> (pricing-count) 0) "Should have fetched pricing data"))))

(module+ test
  (require rackunit/text-ui)
  (run-tests pricing-model-tests))
