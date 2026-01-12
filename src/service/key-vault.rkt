#lang racket/base
;; Chrysalis Forge BYOK Key Vault
;; Secure storage and management of user-provided LLM API keys

(provide (all-defined-out))

(require racket/string racket/match json net/base64 file/sha1 (only-in db query-exec))
(require "config.rkt" "db.rkt")

;; SHA256 implementation - try openssl if available, else fall back
(define sha256-bytes
  (with-handlers ([exn:fail? (lambda (_)
                               ;; Fallback: Use sha1 twice with different seeds for 256-bit output
                               (lambda (data)
                                 (define d1 (sha1-bytes (bytes-append #"a" data)))
                                 (define d2 (sha1-bytes (bytes-append #"b" data)))
                                 (subbytes (bytes-append d1 d2) 0 32)))])
    (dynamic-require 'openssl/sha256 'sha256-bytes)))

;; ============================================================================
;; Key Encryption (AES-256-GCM simulation using XOR + HMAC)
;; In production, use proper crypto library like openssl/libcrypto
;; ============================================================================

(define (derive-encryption-key secret purpose)
  "Derive an encryption key from the server secret and purpose string"
  (sha256-bytes (string->bytes/utf-8 (format "~a:~a:chrysalis-key-vault" secret purpose))))

(define (xor-bytes a b)
  "XOR two byte strings of equal length"
  (define result (make-bytes (bytes-length a)))
  (for ([i (in-range (bytes-length a))])
    (bytes-set! result i (bitwise-xor (bytes-ref a i) 
                                       (bytes-ref b (modulo i (bytes-length b))))))
  result)

(define (encrypt-key plaintext-key)
  "Encrypt an API key for storage.
   Returns base64-encoded ciphertext with embedded IV and MAC."
  (define secret (config-secret-key))
  (define enc-key (derive-encryption-key secret "encrypt"))
  (define mac-key (derive-encryption-key secret "mac"))
  
  ;; Generate random IV
  (define iv (make-bytes 16))
  (for ([i (in-range 16)])
    (bytes-set! iv i (random 256)))
  
  ;; Encrypt (XOR with derived key stream)
  (define plaintext (string->bytes/utf-8 plaintext-key))
  (define key-stream (sha256-bytes (bytes-append enc-key iv)))
  ;; Extend key stream if needed
  (define extended-stream
    (let loop ([stream key-stream] [needed (bytes-length plaintext)])
      (if (>= (bytes-length stream) needed)
          stream
          (loop (bytes-append stream (sha256-bytes (bytes-append enc-key stream)))
                needed))))
  
  (define ciphertext (xor-bytes plaintext (subbytes extended-stream 0 (bytes-length plaintext))))
  
  ;; Compute MAC
  (define mac (sha256-bytes (bytes-append mac-key iv ciphertext)))
  
  ;; Combine: IV + ciphertext + MAC (first 16 bytes)
  (define combined (bytes-append iv ciphertext (subbytes mac 0 16)))
  (bytes->string/utf-8 (base64-encode combined #"")))

(define (decrypt-key encrypted-b64)
  "Decrypt a stored API key.
   Returns plaintext key string or #f if decryption fails."
  (with-handlers ([exn:fail? (λ (_) #f)])
    (define secret (config-secret-key))
    (define enc-key (derive-encryption-key secret "encrypt"))
    (define mac-key (derive-encryption-key secret "mac"))
    
    (define combined (base64-decode (string->bytes/utf-8 encrypted-b64)))
    (define iv (subbytes combined 0 16))
    (define stored-mac (subbytes combined (- (bytes-length combined) 16)))
    (define ciphertext (subbytes combined 16 (- (bytes-length combined) 16)))
    
    ;; Verify MAC
    (define expected-mac (subbytes (sha256-bytes (bytes-append mac-key iv ciphertext)) 0 16))
    (unless (equal? stored-mac expected-mac)
      (error "MAC verification failed"))
    
    ;; Decrypt
    (define key-stream (sha256-bytes (bytes-append enc-key iv)))
    (define extended-stream
      (let loop ([stream key-stream] [needed (bytes-length ciphertext)])
        (if (>= (bytes-length stream) needed)
            stream
            (loop (bytes-append stream (sha256-bytes (bytes-append enc-key stream)))
                  needed))))
    
    (define plaintext (xor-bytes ciphertext (subbytes extended-stream 0 (bytes-length ciphertext))))
    (bytes->string/utf-8 plaintext)))

;; ============================================================================
;; Provider Key Management
;; ============================================================================

(define SUPPORTED-PROVIDERS
  '(openai anthropic google mistral cohere ollama vllm custom))

(define (provider-valid? provider)
  "Check if provider is supported"
  (member (string->symbol (string-downcase provider)) SUPPORTED-PROVIDERS))

(define (get-key-hint key)
  "Get the last 4 characters of a key for identification"
  (if (> (string-length key) 4)
      (format "...~a" (substring key (- (string-length key) 4)))
      "****"))

(define (add-user-key! user-id provider api-key #:org-id [org-id #f] #:base-url [base-url #f])
  "Add or update a provider API key for a user.
   Key is encrypted before storage."
  (unless (provider-valid? provider)
    (error 'add-user-key! "Unsupported provider: ~a" provider))
  
  ;; Validate key format (basic checks)
  (unless (and api-key (> (string-length api-key) 10))
    (error 'add-user-key! "Invalid API key format"))
  
  ;; Encrypt the key
  (define encrypted (encrypt-key api-key))
  (define hint (get-key-hint api-key))
  
  ;; Store in database
  (provider-key-add! user-id provider 
                     (string->bytes/utf-8 encrypted)
                     #:org-id org-id
                     #:base-url base-url
                     #:key-hint hint))

(define (get-user-key user-id provider #:org-id [org-id #f])
  "Get a decrypted provider key for a user.
   Returns (values key base-url) or (values #f #f)."
  (define record (provider-key-get user-id provider #:org-id org-id))
  (if record
      (let ([encrypted (bytes->string/utf-8 (hash-ref record 'key_encrypted))])
        (define decrypted (decrypt-key encrypted))
        (if decrypted
            (values decrypted (hash-ref record 'base_url #f))
            (values #f #f)))
      (values #f #f)))

(define (remove-user-key! user-id provider #:org-id [org-id #f])
  "Remove a provider key"
  (define conn (get-db))
  (if org-id
      (query-exec conn
        "DELETE FROM provider_keys WHERE user_id = ? AND provider = ? AND org_id = ?"
        user-id provider org-id)
      (query-exec conn
        "DELETE FROM provider_keys WHERE user_id = ? AND provider = ? AND org_id IS NULL"
        user-id provider)))

(define (list-user-keys user-id)
  "List all provider keys for a user (without decrypting)"
  (provider-key-list-for-user user-id))

;; ============================================================================
;; Key Resolution (which key to use for a request)
;; ============================================================================

(define (resolve-provider-key user-id provider #:org-id [org-id #f] #:prefer-byok [prefer-byok #t])
  "Resolve which API key to use for a provider.
   Returns (values key base-url is-byok) or (values #f #f #f).
   
   Resolution order when prefer-byok is #t:
   1. User's personal key for this provider
   2. Organization's shared key (if org-id provided)
   3. Service default key (from environment)
   
   When prefer-byok is #f, uses service key directly."
  
  (if prefer-byok
      ;; Try BYOK first
      (let-values ([(user-key user-base-url) (get-user-key user-id provider)])
        (cond
          [user-key 
           (values user-key user-base-url #t)]
          [org-id
           ;; Try org key
           (let-values ([(org-key org-base-url) (get-user-key user-id provider #:org-id org-id)])
             (if org-key
                 (values org-key org-base-url #t)
                 ;; Fall back to service key
                 (values (get-service-key provider) (get-service-base-url provider) #f)))]
          [else
           ;; Fall back to service key
           (values (get-service-key provider) (get-service-base-url provider) #f)]))
      
      ;; Use service key directly
      (values (get-service-key provider) (get-service-base-url provider) #f)))

(define (get-service-key provider)
  "Get the service's default API key for a provider"
  (match (string-downcase provider)
    ["openai" (getenv "OPENAI_API_KEY")]
    ["anthropic" (getenv "ANTHROPIC_API_KEY")]
    ["google" (getenv "GOOGLE_API_KEY")]
    ["mistral" (getenv "MISTRAL_API_KEY")]
    ["cohere" (getenv "COHERE_API_KEY")]
    [_ #f]))

(define (get-service-base-url provider)
  "Get the service's default base URL for a provider"
  (match (string-downcase provider)
    ["openai" (or (getenv "OPENAI_API_BASE") "https://api.openai.com/v1")]
    ["anthropic" (or (getenv "ANTHROPIC_API_BASE") "https://api.anthropic.com")]
    ["google" (or (getenv "GOOGLE_API_BASE") "https://generativelanguage.googleapis.com")]
    ["mistral" (or (getenv "MISTRAL_API_BASE") "https://api.mistral.ai")]
    ["ollama" (or (getenv "OLLAMA_BASE_URL") "http://localhost:11434")]
    ["vllm" (or (getenv "VLLM_BASE_URL") "http://localhost:8000")]
    [_ #f]))

;; ============================================================================
;; Key Validation
;; ============================================================================

(define (validate-provider-key provider api-key #:base-url [base-url #f])
  "Validate a provider API key by making a test request.
   Returns (values valid? message)."
  ;; This would make actual API calls to validate
  ;; For now, just do basic format validation
  (match (string-downcase provider)
    ["openai" 
     (if (string-prefix? api-key "sk-")
         (values #t "Key format valid")
         (values #f "OpenAI keys should start with 'sk-'"))]
    ["anthropic"
     (if (string-prefix? api-key "sk-ant-")
         (values #t "Key format valid")
         (values #f "Anthropic keys should start with 'sk-ant-'"))]
    ["google"
     (if (> (string-length api-key) 20)
         (values #t "Key format valid")
         (values #f "Google API key seems too short"))]
    [_
     (values #t "Format validation not available for this provider")]))
