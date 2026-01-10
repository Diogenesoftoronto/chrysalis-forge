#lang racket/base
(provide calculate-cost update-pricing! fetch-usage-stats)
(require racket/string racket/list net/url json racket/port)

;; Prices in USD per 1M tokens (Input . Output)
;; Initial defaults (OpenAI 2025/2026)
(define DEFAULT-PRICING
  (hash "gpt-5.2"     (cons 5.00 15.00)
        "gpt-4o"      (cons 2.50 10.00)
        "gpt-4o-mini" (cons 0.15 0.60)
        "o1-preview"  (cons 15.00 60.00)
        "o1-mini"     (cons 1.10 4.40)))

(define current-pricing (make-hash (hash->list DEFAULT-PRICING)))
(define pricing-updated? (box #f))

(define (fetch-models url-str)
  (with-handlers ([exn:fail? (λ (e) 
                               (log-warning "Pricing fetch failed for ~a: ~a" url-str (exn-message e))
                               #f)])
    (define url (string->url url-str))
    ;; Use GET request with headers if needed (simple GET for now)
    ;; Note: Some providers might fail without an API Key.
    ;; We rely on standard env var OPENAI_API_KEY if we needed authentication, 
    ;; but simple call/input-url doesn't send auth headers by default. 
    ;; For public endpoints like OpenRouter it's fine. 
    ;; For private proxies, this might fail without auth headers. 
    ;; Given the constraints, we attempt a simple fetch first.
    (define resp (call/input-url url get-pure-port read-json))
    (hash-ref resp 'data '())))

(define (update-pricing!)
  (define base-url (or (getenv "OPENAI_API_BASE") "https://api.openai.com/v1"))
  (define primary-url (string-append (if (string-suffix? base-url "/") (substring base-url 0 (sub1 (string-length base-url))) base-url) "/models"))
  (define fallback-url "https://openrouter.ai/api/v1/models")

  (define (try-update-from! models)
    (cond
      [(or (not models) (null? models)) #f]
      [else
       (define found-pricing? #f)
       (for ([model (in-list models)])
         (define id (hash-ref model 'id))
         (define pricing (hash-ref model 'pricing #f)) ;; Check if 'pricing' field exists
         (when (and pricing (hash? pricing))
           (set! found-pricing? #t)
           (define prompt (string->number (format "~a" (hash-ref pricing 'prompt "0"))))
           (define completion (string->number (format "~a" (hash-ref pricing 'completion "0"))))
           (when (and prompt completion)
             (define simple-id (if (string-prefix? id "openai/") (substring id 7) id))
             (hash-set! current-pricing simple-id 
                        (cons (* prompt 1000000.0) (* completion 1000000.0))))))
       found-pricing?]))

  ;; 1. Try Base URL
  (define base-success? (try-update-from! (fetch-models primary-url)))
  
  ;; 2. If Base URL didn't have pricing data, try Fallback
  (unless base-success?
     (log-info "No pricing data found at ~a. Falling back to OpenRouter." primary-url)
     (try-update-from! (fetch-models fallback-url)))

  (set-box! pricing-updated? #t)
  #t)

(define (fetch-usage-stats [start-time #f])
  (define key (getenv "OPENAI_API_KEY"))
  (unless key 
    (log-warning "OPENAI_API_KEY not found, cannot fetch usage stats.")
    (raise-user-error "OPENAI_API_KEY required"))
  
  (define now (current-seconds))
  (define start (or start-time (- now 86400))) ;; Default to last 24h
  
  (define base-url (or (getenv "OPENAI_API_BASE") "https://api.openai.com/v1"))
  (define clean-base (if (string-suffix? base-url "/") 
                         (substring base-url 0 (sub1 (string-length base-url))) 
                         base-url))
  
  (define usage-url (format "~a/organization/usage/completions?start_time=~a" clean-base start))
  (define cost-url (format "~a/organization/costs?start_time=~a" clean-base start))
  
  (define headers (list (format "Authorization: Bearer ~a" key)
                        "Content-Type: application/json"))
  
  (define (do-fetch label u)
    (with-handlers ([exn:fail? (λ (e) 
                                 (log-warning "Failed ~a fetch (~a): ~a" label u (exn-message e))
                                 #f)])
      (call/input-url (string->url u) 
                      (λ (url) (get-pure-port url headers))
                      read-json)))

  (hash 'completions (do-fetch "usage" usage-url)
        'costs (do-fetch "costs" cost-url)))

(define (get-pricing model)
  ;; Lazy update if not yet done (blocking, but satisfies "run a network request")
  (unless (unbox pricing-updated?)
    (update-pricing!))
    
  ;; Try exact match
  (or (hash-ref current-pricing model #f)
      ;; Try prefix matching
      (for/first ([key (in-list (hash-keys current-pricing))]
                  #:when (string-prefix? model key))
        (hash-ref current-pricing key))
      ;; Default to 0
      (cons 0.0 0.0)))

(define (calculate-cost model tokens-in tokens-out)
  (define prices (get-pricing model))
  (let ([p-in (car prices)]
        [p-out (cdr prices)])
    (+ (* (/ tokens-in 1000000.0) p-in)
       (* (/ tokens-out 1000000.0) p-out))))
