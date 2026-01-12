#lang racket/base
(require net/http-client
         net/url
         json
         racket/file
         racket/list
         racket/string
         racket/hash
         racket/set
         racket/path
         racket/port
         "pricing-model.rkt"
         "../utils/debug.rkt")

(provide (struct-out ModelCapabilities)
         (struct-out ModelStats)
         (struct-out ModelRecord)
         fetch-models-from-endpoint
         parse-model-from-api
         infer-capabilities-from-id
         load-local-models-config
         merge-with-local-config
         init-model-registry!
         register-model!
         list-models
         list-available-models
         get-model
         mark-model-available!
         update-model-stats!
         get-model-success-rate
         save-model-stats!
         load-model-stats!
         detect-provider)

(struct ModelCapabilities
  (id provider max-context reasoning coding speed cost-tier
   supports-tools? supports-vision? best-for description)
  #:transparent)

(struct ModelStats
  (total-calls success-calls total-ms total-cost-usd
   by-task-type by-profile last-used)
  #:transparent)

(struct ModelRecord (caps stats available? disabled?) #:transparent)

(define MODELS-CONFIG-PATH 
  (build-path (find-system-path 'home-dir) ".agentd" "models.json"))
(define STATS-PATH 
  (build-path (find-system-path 'home-dir) ".agentd" "model_stats.json"))

(define model-registry (make-hash))

(define (detect-provider base-url)
  (cond
    [(string-contains? base-url "api.openai.com") 'openai]
    [(string-contains? base-url "openrouter.ai") 'openrouter]
    [(string-contains? base-url "api.anthropic.com") 'anthropic]
    [(string-contains? base-url "api.together.xyz") 'together]
    [(string-contains? base-url "api.groq.com") 'groq]
    [(string-contains? base-url "backboard.io") 'backboard]
    [else 'custom]))

(define (fetch-models-from-endpoint base-url api-key)
  (with-handlers ([exn:fail? (λ (e) 
                               ;; Re-throw with context - caller will handle display
                               (error (format "Failed to fetch models: ~a" (exn-message e))))])
    ;; Validate API key is present and not empty
    (unless (and api-key (string? api-key) (> (string-length api-key) 0))
      (error "API key is required but not provided or is empty"))
    
    (define provider (detect-provider base-url))
    (define clean-base (if (string-suffix? base-url "/")
                           (substring base-url 0 (sub1 (string-length base-url)))
                           base-url))
    
    ;; Build URL and path based on provider
    ;; For Backboard, check if base already includes /api, if so use /models, otherwise use /api/models
    ;; Don't use min_context/max_context filters as they're too restrictive (most models have context_limit > 1)
    (define models-url
      (if (eq? provider 'backboard)
          (let ([has-api? (string-contains? clean-base "/api")])
            (if has-api?
                (string-append clean-base "/models?skip=0&limit=100")
                (string-append clean-base "/api/models?skip=0&limit=100")))
          (string-append clean-base "/models")))
    
    (define parsed-url (string->url models-url))
    (define host (url-host parsed-url))
    (define port (or (url-port parsed-url) (if (equal? (url-scheme parsed-url) "https") 443 80)))
    
    ;; Build full path including query string
    (define path-segments (url-path parsed-url))
    (define path-part (if (null? path-segments)
                          "/models"
                          (string-append "/" (string-join (map path/param-path path-segments) "/"))))
    
    ;; Add query string if present
    (define query-list (url-query parsed-url))
    (define (query-value->string v)
      (cond
        [(string? v) v]
        [(bytes? v) (bytes->string/utf-8 v)]
        [(symbol? v) (symbol->string v)]
        [else (format "~a" v)]))
    (define full-path (if (and query-list (not (null? query-list)))
                          (string-append path-part "?" 
                                       (string-join (for/list ([q query-list])
                                                      (format "~a=~a" 
                                                              (query-value->string (car q))
                                                              (query-value->string (cdr q))))
                                                    "&"))
                          path-part))
    
    ;; Use appropriate header format based on provider
    (define auth-header
      (cond
        [(eq? provider 'backboard)
         (format "X-API-Key: ~a" api-key)]
        [else
         (format "Authorization: Bearer ~a" api-key)]))
    
    (define request-headers (list auth-header
                                 "Content-Type: application/json"))
    
    ;; Helper to mask API key in logs
    (define (mask-api-key header-str)
      (cond
        [(string-contains? header-str "X-API-Key:")
         (string-replace header-str api-key (if (> (string-length api-key) 8)
                                                 (format "~a...~a" (substring api-key 0 4) (substring api-key (- (string-length api-key) 4)))
                                                 "***"))]
        [(string-contains? header-str "Authorization: Bearer")
         (string-replace header-str api-key (if (> (string-length api-key) 8)
                                                 (format "~a...~a" (substring api-key 0 4) (substring api-key (- (string-length api-key) 4)))
                                                 "***"))]
        [else header-str]))
    
    ;; Log raw request details in verbose mode
    (log-debug 2 'models 
               "HTTP Request:\n  Method: GET\n  URL: ~a\n  Host: ~a\n  Port: ~a\n  Path: ~a\n  SSL: ~a\n  Headers:\n~a"
               models-url
               host
               port
               full-path
               (equal? (url-scheme parsed-url) "https")
               (string-join (map (λ (h) (format "    ~a" (mask-api-key h))) request-headers) "\n"))
    
    (define-values (status headers in)
      (http-sendrecv host full-path
                     #:port port
                     #:ssl? (equal? (url-scheme parsed-url) "https")
                     #:method "GET"
                     #:headers request-headers))
    
    (define status-str (bytes->string/utf-8 status))
    (log-debug 2 'models "HTTP Response: ~a" status-str)
    (unless (string-prefix? status-str "HTTP/1.1 200")
      (when (and in (input-port? in))
        (close-input-port in))
      (error (format "HTTP ~a: The /models endpoint may not be available at ~a" status-str models-url)))
    
    ;; Read response body for logging
    (define response-body (port->string in))
    (log-debug 2 'models "Response Body:\n~a" response-body)
    
    (define response (with-handlers ([exn:fail? (λ (e)
                                                   (log-debug 2 'models "Failed to parse JSON: ~a" (exn-message e))
                                                   (error (format "Failed to parse response: ~a" (exn-message e))))])
                       (read-json (open-input-string response-body))))
    
    (log-debug 2 'models "Parsed Response Type: ~a" (if (hash? response) "hash" (if (list? response) "list" "other")))
    (when (hash? response)
      (log-debug 2 'models "Response Keys: ~a" (hash-keys response)))
    
    (define models-list
      (cond
        [(and (hash? response) (hash-has-key? response 'data))
         (define data (hash-ref response 'data))
         (log-debug 2 'models "Found models in 'data' key: ~a items" (if (list? data) (length data) "not a list"))
         data]
        [(and (hash? response) (hash-has-key? response 'models))
         (define models (hash-ref response 'models))
         (log-debug 2 'models "Found models in 'models' key: ~a items" (if (list? models) (length models) "not a list"))
         models]
        [(list? response)
         (log-debug 2 'models "Response is a list: ~a items" (length response))
         response]
        [else
         (log-debug 2 'models "No recognized response format, returning empty list")
         '()]))
    
    (log-debug 2 'models "Final models list: ~a items" (length models-list))
    models-list))

(define (infer-capabilities-from-id id)
  (define id-lower (string-downcase id))
  
  (define reasoning
    (cond
      [(or (string-prefix? id-lower "o1") 
           (string-prefix? id-lower "o3")
           (string-contains? id-lower "reasoning")) 0.95]
      [(string-contains? id-lower "gpt-4") 0.85]
      [(string-contains? id-lower "gpt-5") 0.90]
      [(string-contains? id-lower "claude-3") 0.85]
      [(string-contains? id-lower "claude-4") 0.90]
      [(string-contains? id-lower "gemini-pro") 0.80]
      [(string-contains? id-lower "mini") 0.60]
      [(string-contains? id-lower "flash") 0.65]
      [else 0.70]))
  
  (define coding
    (cond
      [(string-contains? id-lower "codex") 0.95]
      [(string-contains? id-lower "gpt-4") 0.85]
      [(string-contains? id-lower "gpt-5") 0.90]
      [(string-contains? id-lower "claude") 0.85]
      [(string-contains? id-lower "deepseek-coder") 0.90]
      [(string-contains? id-lower "starcoder") 0.85]
      [(string-contains? id-lower "mini") 0.65]
      [else 0.70]))
  
  (define speed
    (cond
      [(string-contains? id-lower "mini") 0.90]
      [(string-contains? id-lower "flash") 0.95]
      [(string-contains? id-lower "turbo") 0.85]
      [(string-contains? id-lower "instant") 0.95]
      [(or (string-prefix? id-lower "o1") (string-prefix? id-lower "o3")) 0.30]
      [(string-contains? id-lower "gpt-4") 0.50]
      [else 0.70]))
  
  (define cost-tier
    (cond
      [(or (string-prefix? id-lower "o1-preview") 
           (string-prefix? id-lower "o3")) 'expensive]
      [(string-contains? id-lower "mini") 'cheap]
      [(string-contains? id-lower "flash") 'cheap]
      [(string-contains? id-lower "gpt-4o") 'moderate]
      [(string-contains? id-lower "gpt-4") 'expensive]
      [(string-contains? id-lower "gpt-5") 'expensive]
      [else 'moderate]))
  
  (define supports-tools?
    (not (or (string-contains? id-lower "instruct")
             (string-contains? id-lower "base")
             (string-contains? id-lower "embedding"))))
  
  (define supports-vision?
    (or (string-contains? id-lower "vision")
        (string-contains? id-lower "4o")
        (string-contains? id-lower "gpt-5")
        (string-contains? id-lower "gemini")
        (and (string-contains? id-lower "claude-3")
             (not (string-contains? id-lower "haiku")))))
  
  (hash 'reasoning reasoning
        'coding coding
        'speed speed
        'cost-tier cost-tier
        'supports-tools? supports-tools?
        'supports-vision? supports-vision?))

(define (get-default-context-window id)
  (define id-lower (string-downcase id))
  (cond
    [(string-contains? id-lower "gpt-4-turbo") 128000]
    [(string-contains? id-lower "gpt-4o") 128000]
    [(string-contains? id-lower "gpt-5") 256000]
    [(or (string-prefix? id-lower "o1") (string-prefix? id-lower "o3")) 128000]
    [(string-contains? id-lower "claude-3") 200000]
    [(string-contains? id-lower "claude-4") 200000]
    [(string-contains? id-lower "gemini") 1000000]
    [(string-contains? id-lower "gpt-4") 8192]
    [(string-contains? id-lower "gpt-3.5") 16385]
    [else 4096]))

(define (infer-best-for id)
  (define id-lower (string-downcase id))
  (cond
    [(or (string-prefix? id-lower "o1") (string-prefix? id-lower "o3")) 
     "complex reasoning, math, analysis"]
    [(string-contains? id-lower "codex") "code generation and completion"]
    [(string-contains? id-lower "mini") "fast responses, simple tasks, cost-efficiency"]
    [(string-contains? id-lower "flash") "high-speed responses, bulk processing"]
    [(string-contains? id-lower "vision") "image analysis, multimodal tasks"]
    [(string-contains? id-lower "embedding") "text embeddings, semantic search"]
    [(or (string-contains? id-lower "gpt-4") (string-contains? id-lower "gpt-5"))
     "general purpose, complex tasks, coding"]
    [(string-contains? id-lower "claude") "analysis, writing, coding, long context"]
    [else "general purpose"]))

(define (parse-model-from-api model-hash provider)
  ;; Handle different API response formats (some use 'name, some use 'id)
  (define id (or (hash-ref model-hash 'id #f)
                 (hash-ref model-hash 'name #f)
                 "unknown"))
  (define inferred (infer-capabilities-from-id id))
  
  ;; Handle different field names for context window
  (define context-window
    (or (hash-ref model-hash 'context_window #f)
        (hash-ref model-hash 'context_length #f)
        (hash-ref model-hash 'context_limit #f)
        (hash-ref model-hash 'max_context #f)
        (get-default-context-window id)))
  
  ;; Handle different field names for tools support
  (define supports-tools?
    (or (hash-ref model-hash 'supports_tools #f)
        (hash-ref model-hash 'supports-tools? #f)
        (hash-ref inferred 'supports-tools?)))
  
  ;; Handle different field names for vision support
  (define supports-vision?
    (or (hash-ref model-hash 'supports_vision #f)
        (hash-ref model-hash 'supports-vision? #f)
        (hash-ref inferred 'supports-vision?)))
  
  (define description
    (or (hash-ref model-hash 'description #f)
        (format "~a model from ~a" id provider)))
  
  (ModelCapabilities
   id
   provider
   context-window
   (hash-ref inferred 'reasoning)
   (hash-ref inferred 'coding)
   (hash-ref inferred 'speed)
   (hash-ref inferred 'cost-tier)
   supports-tools?
   supports-vision?
   (infer-best-for id)
   description))

(define (load-local-models-config)
  (with-handlers ([exn:fail? (λ (e) (hash 'models '() 'disabled '()))])
    (if (file-exists? MODELS-CONFIG-PATH)
        (call-with-input-file MODELS-CONFIG-PATH read-json)
        (hash 'models '() 'disabled '()))))

(define (config-to-capabilities cfg provider)
  (ModelCapabilities
   (hash-ref cfg 'id "custom")
   provider
   (hash-ref cfg 'max-context 128000)
   (hash-ref cfg 'reasoning 0.7)
   (hash-ref cfg 'coding 0.7)
   (hash-ref cfg 'speed 0.7)
   (hash-ref cfg 'cost-tier 'moderate)
   (hash-ref cfg 'supports-tools? #t)
   (hash-ref cfg 'supports-vision? #f)
   (hash-ref cfg 'best-for "general purpose")
   (hash-ref cfg 'description "")))

(define (merge-with-local-config discovered-models local-config)
  (define disabled-ids (list->set (hash-ref local-config 'disabled '())))
  (define local-models (hash-ref local-config 'models '()))
  (define local-by-id 
    (for/hash ([m (in-list local-models)])
      (values (hash-ref m 'id "") m)))
  
  (define merged
    (for/list ([caps (in-list discovered-models)])
      (define id (ModelCapabilities-id caps))
      (define is-disabled (set-member? disabled-ids id))
      (define local-override (hash-ref local-by-id id #f))
      
      (define final-caps
        (if local-override
            (ModelCapabilities
             id
             (ModelCapabilities-provider caps)
             (hash-ref local-override 'max-context (ModelCapabilities-max-context caps))
             (hash-ref local-override 'reasoning (ModelCapabilities-reasoning caps))
             (hash-ref local-override 'coding (ModelCapabilities-coding caps))
             (hash-ref local-override 'speed (ModelCapabilities-speed caps))
             (hash-ref local-override 'cost-tier (ModelCapabilities-cost-tier caps))
             (hash-ref local-override 'supports-tools? (ModelCapabilities-supports-tools? caps))
             (hash-ref local-override 'supports-vision? (ModelCapabilities-supports-vision? caps))
             (hash-ref local-override 'best-for (ModelCapabilities-best-for caps))
             (hash-ref local-override 'description (ModelCapabilities-description caps)))
            caps))
      
      (ModelRecord final-caps (make-empty-stats) #t is-disabled)))
  
  (define discovered-ids 
    (list->set (map ModelCapabilities-id discovered-models)))
  (define custom-models
    (for/list ([m (in-list local-models)]
               #:when (not (set-member? discovered-ids (hash-ref m 'id ""))))
      (define caps (config-to-capabilities m 'custom))
      (ModelRecord caps (make-empty-stats) #t 
                   (set-member? disabled-ids (hash-ref m 'id "")))))
  
  (append merged custom-models))

(define (make-empty-stats)
  (ModelStats 0 0 0 0.0 (hash) (hash) #f))

(define (init-model-registry! #:api-key [key #f] #:api-base [base "https://api.openai.com/v1"])
  (hash-clear! model-registry)
  
  (define provider (detect-provider base))
  (define api-models (fetch-models-from-endpoint base key))
  
  (define discovered-caps
    (for/list ([m (in-list api-models)])
      (parse-model-from-api m provider)))
  
  (define local-config (load-local-models-config))
  (define merged (merge-with-local-config discovered-caps local-config))
  
  (for ([record (in-list merged)])
    (hash-set! model-registry (ModelCapabilities-id (ModelRecord-caps record)) record))
  
  (load-model-stats!)
  
  (length merged))

(define (register-model! caps)
  (define id (ModelCapabilities-id caps))
  (define existing (hash-ref model-registry id #f))
  (define stats (if existing (ModelRecord-stats existing) (make-empty-stats)))
  (hash-set! model-registry id (ModelRecord caps stats #t #f)))

(define (list-models)
  (hash-values model-registry))

(define (list-available-models)
  (filter (λ (r) (and (ModelRecord-available? r) (not (ModelRecord-disabled? r))))
          (hash-values model-registry)))

(define (get-model id)
  (hash-ref model-registry id #f))

(define (mark-model-available! id available?)
  (define existing (hash-ref model-registry id #f))
  (when existing
    (hash-set! model-registry id
               (struct-copy ModelRecord existing [available? available?]))))

(define (update-model-stats! id #:success? success? #:duration-ms ms 
                             #:cost cost #:task-type [tt "general"] #:profile [p 'all])
  (define existing (hash-ref model-registry id #f))
  (when existing
    (define old-stats (ModelRecord-stats existing))
    (define new-by-task
      (hash-set (ModelStats-by-task-type old-stats) tt
                (let ([current (hash-ref (ModelStats-by-task-type old-stats) tt (hash 'calls 0 'success 0))])
                  (hash 'calls (add1 (hash-ref current 'calls 0))
                        'success (+ (hash-ref current 'success 0) (if success? 1 0))))))
    (define new-by-profile
      (hash-set (ModelStats-by-profile old-stats) p
                (let ([current (hash-ref (ModelStats-by-profile old-stats) p (hash 'calls 0 'success 0))])
                  (hash 'calls (add1 (hash-ref current 'calls 0))
                        'success (+ (hash-ref current 'success 0) (if success? 1 0))))))
    
    (define new-stats
      (ModelStats
       (add1 (ModelStats-total-calls old-stats))
       (+ (ModelStats-success-calls old-stats) (if success? 1 0))
       (+ (ModelStats-total-ms old-stats) ms)
       (+ (ModelStats-total-cost-usd old-stats) cost)
       new-by-task
       new-by-profile
       (current-seconds)))
    
    (hash-set! model-registry id
               (struct-copy ModelRecord existing [stats new-stats]))))

(define (get-model-success-rate id #:task-type [tt #f])
  (define record (hash-ref model-registry id #f))
  (cond
    [(not record) #f]
    [tt
     (define task-stats (hash-ref (ModelStats-by-task-type (ModelRecord-stats record)) tt #f))
     (if (and task-stats (> (hash-ref task-stats 'calls 0) 0))
         (/ (hash-ref task-stats 'success 0) (hash-ref task-stats 'calls 1))
         #f)]
    [else
     (define stats (ModelRecord-stats record))
     (if (> (ModelStats-total-calls stats) 0)
         (/ (ModelStats-success-calls stats) (ModelStats-total-calls stats))
         #f)]))

(define (stats-to-json stats)
  (hash 'total-calls (ModelStats-total-calls stats)
        'success-calls (ModelStats-success-calls stats)
        'total-ms (ModelStats-total-ms stats)
        'total-cost-usd (ModelStats-total-cost-usd stats)
        'by-task-type (ModelStats-by-task-type stats)
        'by-profile (for/hash ([(k v) (in-hash (ModelStats-by-profile stats))])
                      (values (symbol->string k) v))
        'last-used (ModelStats-last-used stats)))

(define (json-to-stats h)
  (ModelStats
   (hash-ref h 'total-calls 0)
   (hash-ref h 'success-calls 0)
   (hash-ref h 'total-ms 0)
   (hash-ref h 'total-cost-usd 0.0)
   (hash-ref h 'by-task-type (hash))
   (for/hash ([(k v) (in-hash (hash-ref h 'by-profile (hash)))])
     (values (string->symbol k) v))
   (hash-ref h 'last-used #f)))

(define (save-model-stats!)
  (define stats-hash
    (for/hash ([(id record) (in-hash model-registry)]
               #:when (> (ModelStats-total-calls (ModelRecord-stats record)) 0))
      (values id (stats-to-json (ModelRecord-stats record)))))
  
  (define dir (path-only STATS-PATH))
  (when (and dir (not (directory-exists? dir)))
    (make-directory* dir))
  
  (call-with-output-file STATS-PATH
    (λ (out) (write-json stats-hash out))
    #:exists 'replace))

(define (load-model-stats!)
  (with-handlers ([exn:fail? (λ (e) (void))])
    (when (file-exists? STATS-PATH)
      (define saved (call-with-input-file STATS-PATH read-json))
      (when (hash? saved)
        (for ([(id stats-json) (in-hash saved)])
          (define id-str (if (symbol? id) (symbol->string id) id))
          (define existing (hash-ref model-registry id-str #f))
          (when existing
            (hash-set! model-registry id-str
                       (struct-copy ModelRecord existing 
                                    [stats (json-to-stats stats-json)]))))))))
