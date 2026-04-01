#lang racket/base

(require rackunit
         "../src/llm/pricing-model.rkt"
         "../src/core/runtime.rkt")

(printf "Starting extensive pricing tests...\n")

;; 1. Test Tiered Pricing (Gemini 3.1 Pro)
;; $2.00 / $12.00 (< 200k)
;; $4.00 / $18.00 (> 200k)
(test-case "Gemini 3.1 Pro Tiered Pricing"
  (let ()
    (define model "gemini-3.1-pro-preview")
    
    ;; Under threshold (100k tokens total)
    (define cost-under (calculate-cost model 50000 50000))
    ;; (50,000 / 1M * 2.00) + (50,000 / 1M * 12.00) = 0.1 + 0.6 = 0.7
    (check-= cost-under 0.7 0.0001 "Cost under 200k threshold should be $0.70")
    
    ;; Over threshold (300k tokens total)
    (define cost-over (calculate-cost model 150000 150000))
    ;; (150,000 / 1M * 4.00) + (150,000 / 1M * 18.00) = 0.6 + 2.7 = 3.3
    (check-= cost-over 3.3 0.0001 "Cost over 200k threshold should be $3.30")))

;; 2. Test Complex Pricing (Claude 4.6 Opus)
;; base-in: 5.00, out: 25.00
(test-case "Claude 4.6 Opus Complex Pricing"
  (let ()
    (define model "claude-4-6-opus")
    (define cost (calculate-cost model 100000 100000))
    ;; (100,000 / 1M * 5.00) + (100,000 / 1M * 25.00) = 0.5 + 2.5 = 3.0
    (check-= cost 3.0 0.0001 "Standard calculation should use base-in and out rates")))

;; 3. Test Tiered + Complex (GPT-5.4)
;; < 200k: base-in 2.50, out 15.00
;; > 200k: base-in 5.00, out 22.50
(test-case "GPT-5.4 Tiered + Complex Pricing"
  (let ()
    (define model "gpt-5.4")
    
    ;; Under 200k
    (define cost-under (calculate-cost model 50000 50000))
    ;; (50,000 / 1M * 2.50) + (50,000 / 1M * 15.00) = 0.125 + 0.75 = 0.875
    (check-= cost-under 0.875 0.0001 "GPT-5.4 cost under 200k")
    
    ;; Over 200k
    (define cost-over (calculate-cost model 150000 150000))
    ;; (150,000 / 1M * 5.00) + (150,000 / 1M * 22.50) = 0.75 + 3.375 = 4.125
    (check-= cost-over 4.125 0.0001 "GPT-5.4 cost over 200k")))

;; 4. Test Prefix Matching
(test-case "Pricing Prefix Matching"
  (let ()
    ;; Should match "gpt-5.4-mini" prefix if exact "gpt-5.4-mini-special" is missing
    (define cost (calculate-cost "gpt-5.4-mini-special" 1000000 0))
    (check-= cost 0.75 0.0001 "Should fall back to gpt-5.4-mini base-in rate")))

;; 5. Test Missing Model
(test-case "Unknown Model Pricing"
  (let ()
    (define cost (calculate-cost "not-a-model" 1000000 1000000))
    (check-= cost 0.0 0.0001 "Unknown model should cost 0.0")))

(printf "All pricing tests passed!\n")
