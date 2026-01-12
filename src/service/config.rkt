#lang racket/base
;; Chrysalis Forge Service Configuration
;; Handles loading and validating service configuration from TOML or environment variables

(provide (all-defined-out))

(require json racket/file racket/string racket/match racket/port racket/list)

;; ============================================================================
;; Configuration Structures
;; ============================================================================

(struct ServerConfig (port host) #:transparent)
(struct DatabaseConfig (url pool-size) #:transparent)
(struct AuthConfig (secret-key session-lifetime enable-registration require-email-verify) #:transparent)
(struct BillingConfig (autumn-secret-key stripe-webhook-secret free-tier-daily-limit) #:transparent)
(struct ModelsConfig (default allowed) #:transparent)
(struct RateLimitTier (requests-per-minute requests-per-day) #:transparent)
(struct RateLimitsConfig (free pro team enterprise) #:transparent)
(struct SecurityConfig (allowed-origins trusted-proxies) #:transparent)

(struct ServiceConfig 
  (server database auth billing models rate-limits security) 
  #:transparent)

;; ============================================================================
;; Environment Variable Helpers
;; ============================================================================

(define (env-or key default)
  (or (getenv key) default))

(define (env-or/number key default)
  (define val (getenv key))
  (if val (string->number val) default))

(define (env-or/bool key default)
  (define val (getenv key))
  (cond
    [(not val) default]
    [(member (string-downcase val) '("true" "1" "yes")) #t]
    [(member (string-downcase val) '("false" "0" "no")) #f]
    [else default]))

(define (env-list key default)
  (define val (getenv key))
  (if val
      (map string-trim (string-split val ","))
      default))

;; ============================================================================
;; TOML Parser (Simple subset)
;; ============================================================================

(define (parse-toml-value str)
  "Parse a TOML value string into a Racket value"
  (define trimmed (string-trim str))
  (cond
    ;; Environment variable reference
    [(and (string-prefix? trimmed "${") (string-suffix? trimmed "}"))
     (define var-name (substring trimmed 2 (- (string-length trimmed) 1)))
     (getenv var-name)]
    ;; String (quoted)
    [(or (string-prefix? trimmed "\"") (string-prefix? trimmed "'"))
     (substring trimmed 1 (- (string-length trimmed) 1))]
    ;; Boolean
    [(equal? trimmed "true") #t]
    [(equal? trimmed "false") #f]
    ;; Number
    [(regexp-match? #rx"^-?[0-9]+(\\.[0-9]+)?$" trimmed)
     (string->number trimmed)]
    ;; Array
    [(string-prefix? trimmed "[")
     (define content (substring trimmed 1 (- (string-length trimmed) 1)))
     (if (equal? content "")
         '()
         (map parse-toml-value (string-split content ",")))]
    ;; Inline table (simple case)
    [(string-prefix? trimmed "{")
     (parse-inline-table trimmed)]
    [else trimmed]))

(define (parse-inline-table str)
  "Parse a simple inline TOML table like { key = value, key2 = value2 }"
  (define content (string-trim (substring str 1 (- (string-length str) 1))))
  (if (equal? content "")
      (hash)
      (for/hash ([pair (string-split content ",")])
        (define parts (string-split pair "="))
        (values (string->symbol (string-trim (first parts)))
                (parse-toml-value (string-trim (string-join (rest parts) "=")))))))

(define (parse-toml-file path)
  "Parse a TOML file into a nested hash"
  (define lines (file->lines path))
  (define result (make-hash))
  (define current-section #f)
  
  (for ([line lines])
    (define trimmed (string-trim line))
    (cond
      ;; Skip empty lines and comments
      [(or (equal? trimmed "") (string-prefix? trimmed "#"))
       (void)]
      ;; Section header
      [(and (string-prefix? trimmed "[") (string-suffix? trimmed "]"))
       (define section-name (substring trimmed 1 (- (string-length trimmed) 1)))
       (set! current-section (string->symbol section-name))
       (unless (hash-has-key? result current-section)
         (hash-set! result current-section (make-hash)))]
      ;; Key-value pair
      [(string-contains? trimmed "=")
       (define parts (string-split trimmed "=" #:trim? #f))
       (define key (string->symbol (string-trim (first parts))))
       (define value (parse-toml-value (string-trim (string-join (rest parts) "="))))
       (if current-section
           (hash-set! (hash-ref result current-section) key value)
           (hash-set! result key value))]))
  
  result)

;; ============================================================================
;; Configuration Loading
;; ============================================================================

(define (load-config [config-path #f])
  "Load configuration from TOML file and/or environment variables.
   Environment variables take precedence over file values."
  
  (define file-config
    (cond
      [(and config-path (file-exists? config-path))
       (parse-toml-file config-path)]
      [(file-exists? "chrysalis.toml")
       (parse-toml-file "chrysalis.toml")]
      [(file-exists? (build-path (find-system-path 'home-dir) ".chrysalis" "config.toml"))
       (parse-toml-file (build-path (find-system-path 'home-dir) ".chrysalis" "config.toml"))]
      [else (hash)]))
  
  (define (get-value section key env-key default)
    (or (getenv env-key)
        (and (hash-has-key? file-config section)
             (hash-ref (hash-ref file-config section) key #f))
        default))
  
  (define (get-number section key env-key default)
    (define val (get-value section key env-key #f))
    (cond
      [(not val) default]
      [(number? val) val]
      [(string? val) (or (string->number val) default)]
      [else default]))
  
  (define (get-bool section key env-key default)
    (define val (get-value section key env-key #f))
    (cond
      [(not val) default]
      [(boolean? val) val]
      [(and (string? val) (member (string-downcase val) '("true" "1" "yes"))) #t]
      [(and (string? val) (member (string-downcase val) '("false" "0" "no"))) #f]
      [else default]))
  
  (define (get-list section key env-key default)
    (define env-val (getenv env-key))
    (cond
      [env-val (map string-trim (string-split env-val ","))]
      [(and (hash-has-key? file-config section)
            (hash-ref (hash-ref file-config section) key #f)) 
       => (λ (v) (if (list? v) v (list v)))]
      [else default]))
  
  ;; Build configuration
  (ServiceConfig
   ;; Server
   (ServerConfig
    (get-number 'server 'port "CHRYSALIS_PORT" 8080)
    (get-value 'server 'host "CHRYSALIS_HOST" "127.0.0.1"))
   
   ;; Database
   (DatabaseConfig
    (get-value 'database 'url "CHRYSALIS_DATABASE_URL" 
               (path->string (build-path (find-system-path 'home-dir) ".chrysalis" "chrysalis.db")))
    (get-number 'database 'pool_size "CHRYSALIS_DB_POOL_SIZE" 5))
   
   ;; Auth
   (AuthConfig
    (get-value 'auth 'secret_key "CHRYSALIS_SECRET_KEY" #f)
    (get-number 'auth 'session_lifetime "CHRYSALIS_SESSION_LIFETIME" 86400)
    (get-bool 'auth 'enable_registration "CHRYSALIS_ENABLE_REGISTRATION" #t)
    (get-bool 'auth 'require_email_verify "CHRYSALIS_REQUIRE_EMAIL_VERIFY" #f))
   
   ;; Billing
   (BillingConfig
    (get-value 'billing 'autumn_secret_key "AUTUMN_SECRET_KEY" #f)
    (get-value 'billing 'stripe_webhook_secret "STRIPE_WEBHOOK_SECRET" #f)
    (get-number 'billing 'free_tier_daily_limit "CHRYSALIS_FREE_DAILY_LIMIT" 100))
   
   ;; Models
   (ModelsConfig
    (get-value 'models 'default "CHRYSALIS_DEFAULT_MODEL" "gpt-5.2")
    (get-list 'models 'allowed "CHRYSALIS_ALLOWED_MODELS" 
              '("gpt-5.2" "gpt-4o" "claude-3-opus" "gemini-pro")))
   
   ;; Rate Limits
   (RateLimitsConfig
    (RateLimitTier 10 100)    ; free
    (RateLimitTier 60 1000)   ; pro
    (RateLimitTier 120 -1)    ; team (unlimited daily)
    (RateLimitTier 300 -1))   ; enterprise
   
   ;; Security
   (SecurityConfig
    (get-list 'security 'allowed_origins "CHRYSALIS_ALLOWED_ORIGINS" '("*"))
    (get-list 'security 'trusted_proxies "CHRYSALIS_TRUSTED_PROXIES" '("127.0.0.1")))))

;; ============================================================================
;; Configuration Validation
;; ============================================================================

(define (validate-config! config)
  "Validate configuration and raise errors for critical missing values"
  
  ;; Check for secret key (required for production)
  (unless (AuthConfig-secret-key (ServiceConfig-auth config))
    (eprintf "[CONFIG WARNING] No CHRYSALIS_SECRET_KEY set. Using insecure default for development.~n"))
  
  ;; Validate database URL format
  (define db-url (DatabaseConfig-url (ServiceConfig-database config)))
  (unless (or (string-prefix? db-url "sqlite://")
              (string-prefix? db-url "postgresql://")
              (string-suffix? db-url ".db")
              (file-exists? db-url))
    (eprintf "[CONFIG WARNING] Database URL format may be invalid: ~a~n" db-url))
  
  ;; Check if Autumn is configured for paid features
  (unless (BillingConfig-autumn-secret-key (ServiceConfig-billing config))
    (eprintf "[CONFIG INFO] No AUTUMN_SECRET_KEY set. Billing features disabled.~n"))
  
  config)

;; ============================================================================
;; Configuration Accessors
;; ============================================================================

(define current-config (make-parameter #f))

(define (init-config! [path #f])
  "Initialize and cache the service configuration"
  (current-config (validate-config! (load-config path)))
  (current-config))

(define (get-config)
  "Get current configuration, loading if necessary"
  (or (current-config) (init-config!)))

;; Convenience accessors
(define (config-port) (ServerConfig-port (ServiceConfig-server (get-config))))
(define (config-host) (ServerConfig-host (ServiceConfig-server (get-config))))
(define (config-database-url) (DatabaseConfig-url (ServiceConfig-database (get-config))))
(define (config-secret-key) 
  (or (AuthConfig-secret-key (ServiceConfig-auth (get-config)))
      "dev-insecure-key-do-not-use-in-production"))
(define (config-default-model) (ModelsConfig-default (ServiceConfig-models (get-config))))
(define (config-allowed-models) (ModelsConfig-allowed (ServiceConfig-models (get-config))))
(define (config-autumn-key) (BillingConfig-autumn-secret-key (ServiceConfig-billing (get-config))))
(define (config-free-daily-limit) (BillingConfig-free-tier-daily-limit (ServiceConfig-billing (get-config))))

;; Get rate limit for a plan tier
(define (config-rate-limit tier)
  (define limits (ServiceConfig-rate-limits (get-config)))
  (match tier
    ['free (RateLimitsConfig-free limits)]
    ['pro (RateLimitsConfig-pro limits)]
    ['team (RateLimitsConfig-team limits)]
    ['enterprise (RateLimitsConfig-enterprise limits)]
    [_ (RateLimitsConfig-free limits)]))
