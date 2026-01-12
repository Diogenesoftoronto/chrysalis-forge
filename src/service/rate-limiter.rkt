#lang racket/base
;; Chrysalis Forge Rate Limiter
;; Token bucket / sliding window rate limiting for API requests

(provide (all-defined-out))

(require racket/match racket/date json (only-in db query-maybe-row))
(require "config.rkt" "db.rkt")

;; ============================================================================
;; In-Memory Rate Limit State
;; ============================================================================

;; Key: (user-id . window-key) -> (count . window-start)
(define rate-limit-cache (make-hash))

(define (cache-key user-id window-type)
  "Generate cache key for rate limit bucket"
  (cons user-id window-type))

(define (current-minute)
  "Get current minute as epoch minutes"
  (quotient (current-seconds) 60))

(define (current-day-string)
  "Get current date as YYYY-MM-DD string"
  (parameterize ([date-display-format 'iso-8601])
    (date->string (current-date))))

;; ============================================================================
;; Rate Limit Checking
;; ============================================================================

(define (get-user-tier user-id)
  "Get user's subscription tier for rate limiting.
   Returns: 'free, 'pro, 'team, or 'enterprise"
  ;; TODO: Query actual subscription from database
  ;; For now, default to 'free
  (define conn (get-db))
  (define sub (query-maybe-row conn
    "SELECT plan_id FROM subscriptions WHERE user_id = ? AND status = 'active' LIMIT 1"
    user-id))
  (if sub
      (string->symbol (vector-ref sub 0))
      'free))

(define (check-rate-limit user-id #:org-id [org-id #f])
  "Check if user is within rate limits.
   Returns: (values allowed? limit remaining reset-seconds)"
  (define tier (get-user-tier user-id))
  (define limits (config-rate-limit tier))
  (define rpm-limit (RateLimitTier-requests-per-minute limits))
  (define rpd-limit (RateLimitTier-requests-per-day limits))
  
  ;; Check per-minute rate limit
  (define current-min (current-minute))
  (define minute-key (cache-key user-id 'minute))
  (define minute-bucket (hash-ref rate-limit-cache minute-key (cons 0 current-min)))
  
  ;; Reset bucket if window has passed
  (define minute-count
    (if (= (cdr minute-bucket) current-min)
        (car minute-bucket)
        0))
  
  ;; Check per-day rate limit
  (define today (current-day-string))
  (define daily-usage (usage-get-daily user-id today #:org-id org-id))
  (define daily-count (hash-ref daily-usage 'messages 0))
  
  ;; Determine if allowed
  (cond
    ;; Per-minute limit exceeded
    [(and (> rpm-limit 0) (>= minute-count rpm-limit))
     (values #f rpm-limit 0 (- 60 (modulo (current-seconds) 60)))]
    ;; Per-day limit exceeded (if not unlimited)
    [(and (> rpd-limit 0) (>= daily-count rpd-limit))
     (values #f rpd-limit 0 (seconds-until-midnight))]
    ;; Allowed
    [else
     (values #t rpm-limit (- rpm-limit minute-count 1) (- 60 (modulo (current-seconds) 60)))]))

(define (record-request! user-id #:org-id [org-id #f])
  "Record a request for rate limiting"
  (define current-min (current-minute))
  (define minute-key (cache-key user-id 'minute))
  (define minute-bucket (hash-ref rate-limit-cache minute-key (cons 0 current-min)))
  
  ;; Update minute bucket
  (define new-count
    (if (= (cdr minute-bucket) current-min)
        (add1 (car minute-bucket))
        1))
  (hash-set! rate-limit-cache minute-key (cons new-count current-min)))

(define (seconds-until-midnight)
  "Get seconds until midnight UTC"
  (define now (current-date))
  (define seconds-today (+ (* (date-hour now) 3600)
                           (* (date-minute now) 60)
                           (date-second now)))
  (- 86400 seconds-today))

;; ============================================================================
;; Rate Limit Headers
;; ============================================================================

(define (rate-limit-headers user-id)
  "Generate rate limit headers for response"
  (define-values (allowed? limit remaining reset) (check-rate-limit user-id))
  (list (cons 'x-ratelimit-limit (number->string limit))
        (cons 'x-ratelimit-remaining (number->string (max 0 remaining)))
        (cons 'x-ratelimit-reset (number->string (+ (current-seconds) reset)))))

;; ============================================================================
;; Rate Limit Middleware
;; ============================================================================

(define (with-rate-limit handler)
  "Wrap a handler with rate limiting"
  (lambda (request)
    (define user (hash-ref request 'user #f))
    (unless user
      (return (handler request)))  ; No rate limit for unauthenticated
    
    (define user-id (hash-ref user 'id))
    (define-values (allowed? limit remaining reset) (check-rate-limit user-id))
    
    (if allowed?
        (begin
          (record-request! user-id)
          (let ([response (handler request)])
            (hash-set response 'headers 
                      (append (hash-ref response 'headers '())
                              (rate-limit-headers user-id)))))
        ;; Rate limited
        (hash 'status 429
              'headers (append (list (cons 'content-type "application/json")
                                     (cons 'retry-after (number->string reset)))
                               (rate-limit-headers user-id))
              'body (jsexpr->string 
                     (hash 'error (hash 'message "Rate limit exceeded"
                                        'type "rate_limit_exceeded"
                                        'retry_after reset)))))))

;; Return helper
(define-syntax-rule (return val)
  (raise val))


