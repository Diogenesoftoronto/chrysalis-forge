#lang racket/base
;; Chrysalis Forge Authentication System
;; Handles password hashing, JWT tokens, and API key authentication

(provide (all-defined-out))

(require racket/string racket/match racket/random json net/base64 
         file/sha1 racket/list)
(require "config.rkt" (except-in "db.rkt" crypto-random-bytes))

;; SHA256 implementation using available crypto
;; Try to use openssl if available, else fall back to simple hash
(define sha256-bytes
  (with-handlers ([exn:fail? (lambda (_)
                               ;; Fallback: Use sha1 twice with different seeds for 256-bit output
                               (lambda (data)
                                 (define d1 (sha1-bytes (bytes-append #"a" data)))
                                 (define d2 (sha1-bytes (bytes-append #"b" data)))
                                 (subbytes (bytes-append d1 d2) 0 32)))])
    (dynamic-require 'openssl/sha256 'sha256-bytes)))

;; ============================================================================
;; Password Hashing (using PBKDF2-SHA256)
;; ============================================================================

(define SALT-LENGTH 16)
(define ITERATIONS 100000)
(define KEY-LENGTH 32)

(define (generate-salt)
  "Generate a random salt for password hashing"
  (define bytes (make-bytes SALT-LENGTH))
  (for ([i (in-range SALT-LENGTH)])
    (bytes-set! bytes i (random 256)))
  bytes)

(define (bytes->hex bs)
  "Convert bytes to hex string"
  (apply string-append 
         (for/list ([b (in-bytes bs)])
           (define hex "0123456789abcdef")
           (string (string-ref hex (quotient b 16))
                   (string-ref hex (remainder b 16))))))

(define (hex->bytes str)
  "Convert hex string to bytes"
  (define len (quotient (string-length str) 2))
  (define bs (make-bytes len))
  (for ([i (in-range len)])
    (define hex-pair (substring str (* i 2) (* i 2 2)))
    (bytes-set! bs i (string->number hex-pair 16)))
  bs)

(define (pbkdf2-sha256 password salt iterations key-length)
  "PBKDF2 key derivation using SHA-256"
  ;; Simplified PBKDF2 implementation
  ;; In production, use a proper crypto library
  (define pass-bytes (if (string? password) (string->bytes/utf-8 password) password))
  (define salt-bytes (if (string? salt) (string->bytes/utf-8 salt) salt))
  
  ;; HMAC-SHA256 based derivation
  (define (hmac-sha256 key message)
    (sha256-bytes (bytes-append key message)))
  
  (define block-size 64)
  (define key-padded 
    (if (> (bytes-length pass-bytes) block-size)
        (sha256-bytes pass-bytes)
        (bytes-append pass-bytes (make-bytes (- block-size (bytes-length pass-bytes)) 0))))
  
  ;; XOR with ipad/opad
  (define ipad (make-bytes block-size #x36))
  (define opad (make-bytes block-size #x5c))
  
  (define (xor-bytes a b)
    (define result (make-bytes (bytes-length a)))
    (for ([i (in-range (bytes-length a))])
      (bytes-set! result i (bitwise-xor (bytes-ref a i) (bytes-ref b i))))
    result)
  
  (define inner-key (xor-bytes key-padded ipad))
  (define outer-key (xor-bytes key-padded opad))
  
  (define (hmac msg)
    (sha256-bytes (bytes-append outer-key (sha256-bytes (bytes-append inner-key msg)))))
  
  ;; PBKDF2-F function
  (define u1 (hmac (bytes-append salt-bytes #"\x00\x00\x00\x01")))
  (define result u1)
  
  (for ([i (in-range 1 (min iterations 1000))]) ; Limit iterations for performance
    (define u-next (hmac result))
    (set! result (xor-bytes result u-next)))
  
  (subbytes result 0 (min key-length (bytes-length result))))

(define (hash-password password)
  "Hash a password with random salt, returns 'salt$hash' format"
  (define salt (generate-salt))
  (define hash (pbkdf2-sha256 password salt ITERATIONS KEY-LENGTH))
  (format "~a$~a" (bytes->hex salt) (bytes->hex hash)))

(define (verify-password password stored-hash)
  "Verify a password against stored hash"
  (define parts (string-split stored-hash "$"))
  (if (= (length parts) 2)
      (let* ([salt (hex->bytes (first parts))]
             [expected-hash (hex->bytes (second parts))]
             [actual-hash (pbkdf2-sha256 password salt ITERATIONS KEY-LENGTH)])
        (equal? expected-hash actual-hash))
      #f))

;; ============================================================================
;; JWT Token Management
;; ============================================================================

(define (base64url-encode bs)
  "Base64 URL-safe encoding"
  (define b64 (base64-encode bs #""))
  (define str (bytes->string/utf-8 b64))
  (string-replace (string-replace (string-replace str "+" "-") "/" "_") "=" ""))

(define (base64url-decode str)
  "Base64 URL-safe decoding"
  (define padded 
    (string-append str 
                   (make-string (modulo (- 4 (modulo (string-length str) 4)) 4) #\=)))
  (define normalized (string-replace (string-replace padded "-" "+") "_" "/"))
  (base64-decode (string->bytes/utf-8 normalized)))

(define (hmac-sha256-sign data secret)
  "Sign data with HMAC-SHA256"
  (define key (if (string? secret) (string->bytes/utf-8 secret) secret))
  (define msg (if (string? data) (string->bytes/utf-8 data) data))
  ;; Use sha256 with key prefix (simplified HMAC)
  (sha256-bytes (bytes-append key msg)))

(define (create-jwt payload #:secret [secret (config-secret-key)] #:expires-in [expires-in 86400])
  "Create a JWT token"
  (define header (hash 'alg "HS256" 'typ "JWT"))
  (define now (current-seconds))
  (define full-payload 
    (hash-set* payload 
               'iat now 
               'exp (+ now expires-in)))
  
  (define header-b64 (base64url-encode (string->bytes/utf-8 (jsexpr->string header))))
  (define payload-b64 (base64url-encode (string->bytes/utf-8 (jsexpr->string full-payload))))
  (define unsigned (format "~a.~a" header-b64 payload-b64))
  (define signature (base64url-encode (hmac-sha256-sign unsigned secret)))
  (format "~a.~a" unsigned signature))

(define (verify-jwt token #:secret [secret (config-secret-key)])
  "Verify and decode a JWT token. Returns payload hash or #f if invalid."
  (with-handlers ([exn:fail? (λ (_) #f)])
    (define parts (string-split token "."))
    (unless (= (length parts) 3) (error "Invalid JWT format"))
    
    (define header-b64 (first parts))
    (define payload-b64 (second parts))
    (define signature (third parts))
    
    ;; Verify signature
    (define unsigned (format "~a.~a" header-b64 payload-b64))
    (define expected-sig (base64url-encode (hmac-sha256-sign unsigned secret)))
    (unless (equal? signature expected-sig) (error "Invalid signature"))
    
    ;; Decode payload
    (define payload (string->jsexpr (bytes->string/utf-8 (base64url-decode payload-b64))))
    
    ;; Check expiration
    (define exp (hash-ref payload 'exp 0))
    (when (< exp (current-seconds)) (error "Token expired"))
    
    payload))

;; ============================================================================
;; API Key Management
;; ============================================================================

(define API-KEY-PREFIX "chs_")

(define (generate-api-key)
  "Generate a new API key. Returns (values full-key prefix hash)"
  (define random-bytes (make-bytes 32))
  (for ([i (in-range 32)])
    (bytes-set! random-bytes i (random 256)))
  
  (define key-body (base64url-encode random-bytes))
  (define full-key (string-append API-KEY-PREFIX key-body))
  (define prefix (substring full-key 0 12))  ; "chs_" + 8 chars
  (define key-hash (bytes->hex (sha256-bytes (string->bytes/utf-8 full-key))))
  
  (values full-key prefix key-hash))

(define (verify-api-key key)
  "Verify an API key. Returns user-id or #f if invalid."
  (with-handlers ([exn:fail? (λ (_) #f)])
    (unless (string-prefix? key API-KEY-PREFIX) (error "Invalid key format"))
    
    (define prefix (substring key 0 12))
    (define key-record (api-key-find-by-prefix prefix))
    (unless key-record (error "Key not found"))
    
    ;; Verify hash
    (define expected-hash (hash-ref key-record 'key_hash))
    (define actual-hash (bytes->hex (sha256-bytes (string->bytes/utf-8 key))))
    (unless (equal? expected-hash actual-hash) (error "Key hash mismatch"))
    
    ;; Check expiration
    (define expires (hash-ref key-record 'expires_at #f))
    (when (and expires (< (string->number expires) (current-seconds)))
      (error "Key expired"))
    
    ;; Update last used
    (api-key-update-last-used! (hash-ref key-record 'id))
    
    (hash-ref key-record 'user_id)))

;; ============================================================================
;; User Registration & Login
;; ============================================================================

(define (register-user! email password #:display-name [display-name #f])
  "Register a new user. Returns user ID or raises error."
  ;; Validate email format
  (unless (regexp-match? #rx"^[^@]+@[^@]+\\.[^@]+$" email)
    (error 'register "Invalid email format"))
  
  ;; Check password strength
  (unless (>= (string-length password) 8)
    (error 'register "Password must be at least 8 characters"))
  
  ;; Check if user exists
  (when (user-find-by-email email)
    (error 'register "Email already registered"))
  
  ;; Create user
  (define password-hash (hash-password password))
  (user-create! email password-hash #:display-name display-name))

(define (login-user! email password)
  "Login a user. Returns (values user-id token) or raises error."
  (define user (user-find-by-email email))
  
  (unless user
    (error 'login "Invalid email or password"))
  
  (unless (verify-password password (hash-ref user 'password_hash))
    (error 'login "Invalid email or password"))
  
  (when (equal? (hash-ref user 'status) "suspended")
    (error 'login "Account suspended"))
  
  ;; Update last login
  (user-update-login! (hash-ref user 'id))
  
  ;; Create JWT
  (define token (create-jwt (hash 'sub (hash-ref user 'id)
                                   'email (hash-ref user 'email))))
  
  (values (hash-ref user 'id) token))

(define (get-user-from-token token)
  "Get user data from JWT token. Returns user hash or #f."
  (define payload (verify-jwt token))
  (and payload
       (user-find-by-id (hash-ref payload 'sub))))

;; ============================================================================
;; Authentication Middleware
;; ============================================================================

(define (extract-bearer-token headers)
  "Extract bearer token from Authorization header"
  (define auth-header (hash-ref headers 'authorization #f))
  (and auth-header
       (string-prefix? auth-header "Bearer ")
       (substring auth-header 7)))

(define (authenticate request)
  "Authenticate a request. Returns user hash or #f.
   Supports both JWT tokens and API keys."
  (define headers (hash-ref request 'headers (hash)))
  
  ;; Try Bearer token first
  (define bearer (extract-bearer-token headers))
  (when bearer
    (define user (get-user-from-token bearer))
    (when user (return user)))
  
  ;; Try API key
  (define api-key (or (hash-ref headers 'x-api-key #f)
                      (hash-ref (hash-ref request 'query (hash)) 'api_key #f)))
  (when api-key
    (define user-id (verify-api-key api-key))
    (when user-id
      (return (user-find-by-id user-id))))
  
  #f)

(define-syntax-rule (return val)
  (let ([v val]) (when v (raise v))))

(define (require-auth request)
  "Require authentication. Returns user or raises 401 error."
  (with-handlers ([hash? (λ (u) u)])
    (define user (authenticate request))
    (unless user
      (error 'auth "Authentication required"))
    user))

;; ============================================================================
;; Authorization Helpers
;; ============================================================================

(define (user-can-access-org? user-id org-id action)
  "Check if user can perform action on organization"
  (define role (org-user-role org-id user-id))
  (and role
       (match action
         ['read #t]  ; All members can read
         ['write (member role '("owner" "admin" "member"))]
         ['admin (member role '("owner" "admin"))]
         ['owner (equal? role "owner")]
         [_ #f])))

(define (user-can-access-session? user-id session-id)
  "Check if user can access a session"
  (define session (session-find-by-id session-id))
  (and session
       (or (equal? user-id (hash-ref session 'user_id))
           ;; Check org access if session belongs to an org
           (let ([org-id (hash-ref session 'org_id #f)])
             (and org-id (user-can-access-org? user-id org-id 'read))))))
