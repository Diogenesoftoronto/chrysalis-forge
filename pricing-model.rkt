#lang racket/base
(provide calculate-cost)
(require racket/string)

;; Prices in USD per 1M tokens (Input . Output)
(define PRICING-TABLE
  (hash "gpt-4o" (cons 5.0 15.0)      ; Example pricing
        "gpt-4o-mini" (cons 0.15 0.6)))

(define (calculate-cost model tokens-in tokens-out)
  (define prices (hash-ref PRICING-TABLE model #f))
  (if prices
      (let ([p-in (car prices)]
            [p-out (cdr prices)])
        (+ (* (/ tokens-in 1000000.0) p-in)
           (* (/ tokens-out 1000000.0) p-out)))
      0.0))
