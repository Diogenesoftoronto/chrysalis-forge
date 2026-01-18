#lang racket/base
(provide levenshtein format-duration format-number
         session-start-time session-input-tokens session-output-tokens
         session-turn-count session-model-usage session-tool-usage
         total-session-cost
         ;; Setters for mutable session state
         session-add-cost! session-add-tokens! session-increment-turns!
         session-record-model-usage!
         model-param vision-model-param base-url-param
         budget-param timeout-param priority-param pretty-param
         interactive-param attachments
         current-security-level llm-judge-param llm-judge-model-param
         env-api-key api-key)

(require racket/format)

(define session-start-time (current-seconds))
(define total-session-cost 0.0)
(define session-input-tokens 0)
(define session-output-tokens 0)
(define session-turn-count 0)
(define session-model-usage (make-hash))
(define session-tool-usage (make-hash))

(define (session-add-cost! amount)
  (set! total-session-cost (+ total-session-cost amount)))

(define (session-add-tokens! in-tok out-tok)
  (set! session-input-tokens (+ session-input-tokens in-tok))
  (set! session-output-tokens (+ session-output-tokens out-tok)))

(define (session-increment-turns!)
  (set! session-turn-count (add1 session-turn-count)))

(define (session-record-model-usage! model in-tok out-tok cost)
  (define model-entry (hash-ref session-model-usage model (hash 'in 0 'out 0 'calls 0 'cost 0.0)))
  (hash-set! session-model-usage model
             (hash 'in (+ (hash-ref model-entry 'in) in-tok)
                   'out (+ (hash-ref model-entry 'out) out-tok)
                   'calls (add1 (hash-ref model-entry 'calls))
                   'cost (+ (hash-ref model-entry 'cost) cost))))

(define env-api-key (getenv "OPENAI_API_KEY"))
(define api-key env-api-key)

(define base-url-param (make-parameter (or (getenv "OPENAI_API_BASE") "https://api.openai.com/v1")))
(define model-param (make-parameter (or (getenv "MODEL") (getenv "CHRYSALIS_DEFAULT_MODEL") "gpt-5.2")))
(define vision-model-param (make-parameter (or (getenv "VISION_MODEL") (model-param))))
(define interactive-param (make-parameter (or (getenv "INTERACTIVE") #f)))
(define attachments (make-parameter '()))

(define budget-param (make-parameter (or (getenv "BUDGET") +inf.0)))
(define timeout-param (make-parameter (or (getenv "TIMEOUT") +inf.0)))
(define pretty-param (make-parameter (or (getenv "PRETTY") "none")))

(define current-security-level (make-parameter 1))
(define priority-param (make-parameter (or (getenv "PRIORITY") "best")))

(define llm-judge-param (make-parameter (or (getenv "LLM_JUDGE") #f)))
(define llm-judge-model-param (make-parameter (or (getenv "LLM_JUDGE_MODEL") (model-param))))

(define (levenshtein s1 s2)
  (let* ([len1 (string-length s1)]
         [len2 (string-length s2)]
         [matrix (make-vector (add1 len1))])
    (for ([i (in-range (add1 len1))])
      (vector-set! matrix i (make-vector (add1 len2))))
    (for ([i (in-range (add1 len1))])
      (vector-set! (vector-ref matrix i) 0 i))
    (for ([j (in-range (add1 len2))])
      (vector-set! (vector-ref matrix 0) j j))
    (for ([i (in-range 1 (add1 len1))])
      (for ([j (in-range 1 (add1 len2))])
        (let ([cost (if (char=? (string-ref s1 (sub1 i)) (string-ref s2 (sub1 j))) 0 1)])
          (vector-set! (vector-ref matrix i) j
                       (min (add1 (vector-ref (vector-ref matrix (sub1 i)) j))
                            (add1 (vector-ref (vector-ref matrix i) (sub1 j)))
                            (+ cost (vector-ref (vector-ref matrix (sub1 i)) (sub1 j))))))))
    (vector-ref (vector-ref matrix len1) len2)))

(define (format-duration seconds)
  (define mins (quotient seconds 60))
  (define secs (remainder seconds 60))
  (if (> mins 0)
      (format "~am ~as" mins secs)
      (format "~as" secs)))

(define (format-number n)
  (define s (number->string n))
  (define len (string-length s))
  (if (<= len 3) s
      (let loop ([i (- len 3)] [acc (substring s (- len 3))])
        (if (<= i 0)
            (string-append (substring s 0 i) acc)
            (loop (- i 3) (string-append "," (substring s (max 0 (- i 3)) i) acc))))))
