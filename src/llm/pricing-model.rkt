#lang racket/base
(provide calculate-cost update-pricing! fetch-usage-stats 
         reset-pricing! clear-pricing! pricing-count)
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

(define (reset-pricing!)
  (set! current-pricing (make-hash (hash->list DEFAULT-PRICING)))
  (set-box! pricing-updated? #t))

(define (clear-pricing!)
  (set! current-pricing (make-hash))
  (set-box! pricing-updated? #f))

(define (pricing-count) (hash-count current-pricing))

(define (fetch-json url-str)
  (with-handlers ([exn:fail? (λ (e) 
                               (log-warning "Pricing fetch failed for ~a: ~a" url-str (exn-message e))
                               #f)])
    (define url (string->url url-str))
    (call/input-url url get-pure-port read-json)))

;; Fetch pricing from Portkey's free API (no API key required)
;; Returns cents per token - we convert to dollars per 1M tokens
(define (fetch-portkey-pricing! provider)
  (define url (format "https://api.portkey.ai/model-configs/pricing/~a" provider))
  (define resp (fetch-json url))
  (cond
    [(not resp) #f]
    [(hash? resp)
     (define found-any? #f)
     (for ([(model-id config) (in-hash resp)])
       (when (and (hash? config) (not (equal? model-id 'default)))
         (define pricing (hash-ref config 'pricing_config #f))
         (when (and pricing (hash? pricing))
           (define pay (hash-ref pricing 'pay_as_you_go #f))
           (when (and pay (hash? pay))
             ;; Portkey prices are in cents per token
             ;; Convert to dollars per 1M tokens: cents * 10000
             (define input-cents (hash-ref pay 'input_tokens 0))
             (define output-cents (hash-ref pay 'output_tokens 0))
             (when (and (number? input-cents) (number? output-cents))
               (set! found-any? #t)
               (hash-set! current-pricing (symbol->string model-id)
                          (cons (* input-cents 10000.0) (* output-cents 10000.0))))))))
     found-any?]
    [else #f]))

;; Fetch from OpenRouter-style API (prices are per-token, multiply by 1M)
(define (fetch-openrouter-style-pricing! url)
  (define resp (fetch-json url))
  (define models (and resp (hash-ref resp 'data '())))
  (cond
    [(or (not models) (null? models)) #f]
    [else
     (define found-pricing? #f)
     (for ([model (in-list models)])
       (define id (hash-ref model 'id ""))
       (define pricing (hash-ref model 'pricing #f))
       (when (and pricing (hash? pricing))
         (set! found-pricing? #t)
         (define prompt (string->number (format "~a" (hash-ref pricing 'prompt "0"))))
         (define completion (string->number (format "~a" (hash-ref pricing 'completion "0"))))
         (when (and prompt completion)
           (define simple-id (if (string-prefix? id "openai/") (substring id 7) id))
           (hash-set! current-pricing simple-id 
                      (cons (* prompt 1000000.0) (* completion 1000000.0))))))
     found-pricing?]))

(define (update-pricing!)
  (define base-url (or (getenv "OPENAI_API_BASE") "https://api.openai.com/v1"))
  (define clean-base (if (string-suffix? base-url "/") 
                         (substring base-url 0 (sub1 (string-length base-url))) 
                         base-url))
  
  ;; 1. Try configured base URL first (may have custom/enterprise pricing)
  (define base-success? (fetch-openrouter-style-pricing! (string-append clean-base "/models")))
  
  ;; 2. Fallback to Portkey (free, 2300+ models, no API key)
  (unless base-success?
    (log-info "No pricing at ~a. Trying Portkey." clean-base)
    (define portkey-providers '("openai" "anthropic" "google" "deepseek" "mistral-ai" "cohere" "groq"))
    (define portkey-success? 
      (for/or ([provider (in-list portkey-providers)])
        (fetch-portkey-pricing! provider)))
    
    ;; 3. Last resort: OpenRouter
    (unless portkey-success?
      (log-info "Portkey unavailable. Falling back to OpenRouter.")
      (fetch-openrouter-style-pricing! "https://openrouter.ai/api/v1/models")))

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
