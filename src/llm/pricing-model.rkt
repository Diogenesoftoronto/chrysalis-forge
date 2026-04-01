#lang racket/base
(provide calculate-cost update-pricing! fetch-usage-stats 
         reset-pricing! clear-pricing! pricing-count)
(require racket/string racket/list net/url json racket/port)

;; Prices in USD per 1M tokens (Input . Output)
;; Current 2026 Market Rates (April 2026)
;; Prices in USD per 1M tokens (Input . Output)
;; Current 2026 Market Rates (April 2026)
;; Supports tiered pricing: (list (cons threshold-max (cons/hash rates)) ...)
;; Supports complex pricing: (hash 'base-in X 'cache-hit A 'out B ...)
(define DEFAULT-PRICING
  (hash 
        ;; OpenAI GPT-5 Era (Tiered + Cache)
        "gpt-5.4-pro"
        (list (cons 200000 (hash 'base-in 30.00 'out 180.00))
              (cons +inf.0  (hash 'base-in 60.00 'out 270.00)))
        
        "gpt-5.4"
        (list (cons 200000 (hash 'base-in 2.50 'cache-hit 0.25 'out 15.00))
              (cons +inf.0  (hash 'base-in 5.00 'cache-hit 0.50 'out 22.50)))
        
        "gpt-5.4-mini" (hash 'base-in 0.75 'cache-hit 0.075 'out 4.50)
        "gpt-5.4-nano" (hash 'base-in 0.20 'cache-hit 0.02  'out 1.25)
        
        "o3-mini"         (cons 1.10 4.40)
        
        ;; Anthropic Claude 4/3 Era (Detailed Cache Pricing)
        "claude-4-6-opus"   (hash 'base-in 5.00  'cache-write-5m 6.25  'cache-write-1h 10.00 'cache-hit 0.50 'out 25.00)
        "claude-4-5-opus"   (hash 'base-in 5.00  'cache-write-5m 6.25  'cache-write-1h 10.00 'cache-hit 0.50 'out 25.00)
        "claude-4-1-opus"   (hash 'base-in 15.00 'cache-write-5m 18.75 'cache-write-1h 30.00 'cache-hit 1.50 'out 75.00)
        "claude-4-opus"     (hash 'base-in 15.00 'cache-write-5m 18.75 'cache-write-1h 30.00 'cache-hit 1.50 'out 75.00)
        
        "claude-4-6-sonnet" (hash 'base-in 3.00  'cache-write-5m 3.75  'cache-write-1h 6.00  'cache-hit 0.30 'out 15.00)
        "claude-4-5-sonnet" (hash 'base-in 3.00  'cache-write-5m 3.75  'cache-write-1h 6.00  'cache-hit 0.30 'out 15.00)
        "claude-4-sonnet"   (hash 'base-in 3.00  'cache-write-5m 3.75  'cache-write-1h 6.00  'cache-hit 0.30 'out 15.00)
        "claude-3-7-sonnet" (hash 'base-in 3.00  'cache-write-5m 3.75  'cache-write-1h 6.00  'cache-hit 0.30 'out 15.00) ;; Deprecated
        
        "claude-4-5-haiku"  (hash 'base-in 1.00  'cache-write-5m 1.25  'cache-write-1h 2.00  'cache-hit 0.10 'out 5.00)
        "claude-3-5-haiku"  (hash 'base-in 0.80  'cache-write-5m 1.00  'cache-write-1h 1.60  'cache-hit 0.08 'out 4.00)
        
        "claude-3-opus"     (hash 'base-in 15.00 'cache-write-5m 18.75 'cache-write-1h 30.00 'cache-hit 1.50 'out 75.00) ;; Deprecated
        "claude-3-haiku"    (hash 'base-in 0.25  'cache-write-5m 0.30  'cache-write-1h 0.50  'cache-hit 0.03 'out 1.25)
        
        ;; Google Gemini 3 Era (Tiered Pricing)
        "gemini-3.1-pro-preview" 
        (list (cons 200000 (cons 2.00 12.00))
              (cons +inf.0 (cons 4.00 18.00)))
        
        "gemini-3-flash-preview" (cons 0.40 2.40)
        
        ;; Open Frontier Leaders
        "deepseek-v3"     (cons 0.14 0.28)
        "deepseek-r2"     (cons 0.55 2.19)
        "kimi-k2-5"       (cons 0.60 2.50)
        "glm-5"           (cons 1.00 3.20)
        "glm-5-turbo"     (cons 1.20 4.00)))
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

(define (log-warning fmt . args) (apply eprintf (string-append "WARNING: " fmt "\n") args))
(define (log-info fmt . args) (apply eprintf (string-append "INFO: " fmt "\n") args))

(define (get-pricing model [context-tokens 0])
  ;; In test/offline mode, we skip network update
  ;; Use environment variable or global flag to skip
  (unless (or (unbox pricing-updated?) (getenv "SKIP_PRICING_UPDATE"))
    (with-handlers ([exn:fail? (λ (e) (log-warning "Lazy pricing update failed: ~a" (exn-message e)))])
      (update-pricing!)))
    
  ;; Try exact match
  (define entry 
    (or (hash-ref current-pricing model #f)
        ;; Try prefix matching (longest match wins)
        (let* ([matching-keys (filter (λ (key) (string-prefix? model key)) (hash-keys current-pricing))]
               [sorted-keys (sort matching-keys > #:key string-length)])
          (if (null? sorted-keys)
              #f
              (hash-ref current-pricing (car sorted-keys))))))
  
  (define resolved
    (cond
      [(not entry) (cons 0.0 0.0)]
      [(list? entry)
       ;; Resolve tiered pricing based on context length
       (or (for/first ([tier (in-list entry)]
                       #:when (<= context-tokens (car tier)))
             (cdr tier))
           (cdr (last entry)))]
      [else entry]))
  
  (if (hash? resolved)
      ;; Resolve complex pricing to base rates for standard calculation
      (cons (hash-ref resolved 'base-in 0.0) (hash-ref resolved 'out 0.0))
      resolved))

(define (calculate-cost model tokens-in tokens-out)
  (define total (+ tokens-in tokens-out))
  (define prices (get-pricing model total))
  (let ([p-in (car prices)]
        [p-out (cdr prices)])
    (+ (* (/ tokens-in 1000000.0) p-in)
       (* (/ tokens-out 1000000.0) p-out))))
