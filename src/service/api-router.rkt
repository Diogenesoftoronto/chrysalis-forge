#lang racket/base
;; Chrysalis Forge API Router
;; RESTful API routes with OpenAI-compatible endpoints

(provide (all-defined-out))

(require racket/string racket/match json racket/port racket/date racket/list)
(require "config.rkt" "db.rkt" "auth.rkt" (except-in "key-vault.rkt" sha256-bytes))

;; ============================================================================
;; HTTP Response Helpers
;; ============================================================================

(define (json-response data #:status [status 200] #:headers [extra-headers '()])
  "Create a JSON HTTP response"
  (define body (jsexpr->string data))
  (hash 'status status
        'headers (append (list (cons 'content-type "application/json")
                               (cons 'content-length (number->string (string-length body))))
                         extra-headers)
        'body body))

(define (error-response message #:status [status 400] #:code [code #f])
  "Create an error response"
  (json-response 
   (hash 'error (hash 'message message 
                      'type (match status
                              [400 "invalid_request_error"]
                              [401 "authentication_error"]
                              [403 "permission_denied"]
                              [404 "not_found"]
                              [429 "rate_limit_exceeded"]
                              [500 "server_error"]
                              [_ "error"])
                      'code (or code "error")))
   #:status status))

(define (not-found-response [message "Resource not found"])
  (error-response message #:status 404))

(define (unauthorized-response [message "Authentication required"])
  (error-response message #:status 401))

(define (forbidden-response [message "Permission denied"])
  (error-response message #:status 403))

;; ============================================================================
;; Request Parsing
;; ============================================================================

(define (parse-json-body request)
  "Parse JSON from request body"
  (define body (hash-ref request 'body ""))
  (if (or (not body) (equal? body ""))
      (hash)
      (with-handlers ([exn:fail? (λ (_) (hash))])
        (string->jsexpr body))))

(define (get-path-param request param)
  "Get a path parameter from request"
  (hash-ref (hash-ref request 'path-params (hash)) param #f))

(define (get-query-param request param [default #f])
  "Get a query parameter from request"
  (hash-ref (hash-ref request 'query (hash)) param default))

;; ============================================================================
;; Authentication Endpoints
;; ============================================================================

(define (handle-register request)
  "POST /auth/register - Register a new user"
  (define body (parse-json-body request))
  (define email (hash-ref body 'email #f))
  (define password (hash-ref body 'password #f))
  (define display-name (hash-ref body 'display_name #f))
  
  (unless (and email password)
    (return (error-response "Email and password required")))
  
  (with-handlers ([exn:fail? (λ (e) (error-response (exn-message e)))])
    (define user-id (register-user! email password #:display-name display-name))
    (define-values (_ token) (login-user! email password))
    
    (json-response 
     (hash 'id user-id
           'email email
           'display_name display-name
           'token token)
     #:status 201)))

(define (handle-login request)
  "POST /auth/login - Login user"
  (define body (parse-json-body request))
  (define email (hash-ref body 'email #f))
  (define password (hash-ref body 'password #f))
  
  (unless (and email password)
    (return (error-response "Email and password required")))
  
  (with-handlers ([exn:fail? (λ (e) (error-response (exn-message e) #:status 401))])
    (define-values (user-id token) (login-user! email password))
    (define user (user-find-by-id user-id))
    
    (json-response
     (hash 'id user-id
           'email (hash-ref user 'email)
           'display_name (hash-ref user 'display_name)
           'token token))))

(define (handle-me request)
  "GET /users/me - Get current user"
  (define user (require-auth request))
  (unless user (return (unauthorized-response)))
  
  (json-response
   (hash 'id (hash-ref user 'id)
         'email (hash-ref user 'email)
         'display_name (hash-ref user 'display_name)
         'avatar_url (hash-ref user 'avatar_url)
         'created_at (hash-ref user 'created_at))))

;; ============================================================================
;; Organization Endpoints
;; ============================================================================

(define (handle-list-orgs request)
  "GET /orgs - List user's organizations"
  (define user (require-auth request))
  (unless user (return (unauthorized-response)))
  
  (define orgs (org-list-for-user (hash-ref user 'id)))
  (json-response (hash 'data orgs)))

(define (handle-create-org request)
  "POST /orgs - Create an organization"
  (define user (require-auth request))
  (unless user (return (unauthorized-response)))
  
  (define body (parse-json-body request))
  (define name (hash-ref body 'name #f))
  (define slug (hash-ref body 'slug #f))
  
  (unless (and name slug)
    (return (error-response "Name and slug required")))
  
  ;; Validate slug format
  (unless (regexp-match? #rx"^[a-z0-9-]+$" slug)
    (return (error-response "Slug must be lowercase letters, numbers, and hyphens only")))
  
  (with-handlers ([exn:fail? (λ (e) (error-response (exn-message e)))])
    (define org-id (org-create! name slug (hash-ref user 'id)))
    (define org (org-find-by-id org-id))
    (json-response org #:status 201)))

(define (handle-get-org request)
  "GET /orgs/{id} - Get organization details"
  (define user (require-auth request))
  (unless user (return (unauthorized-response)))
  
  (define org-id (get-path-param request 'id))
  (define org (org-find-by-id org-id))
  
  (unless org (return (not-found-response)))
  (unless (user-can-access-org? (hash-ref user 'id) org-id 'read)
    (return (forbidden-response)))
  
  (json-response org))

(define (handle-list-org-members request)
  "GET /orgs/{id}/members - List organization members"
  (define user (require-auth request))
  (unless user (return (unauthorized-response)))
  
  (define org-id (get-path-param request 'id))
  (unless (user-can-access-org? (hash-ref user 'id) org-id 'read)
    (return (forbidden-response)))
  
  (define members (org-get-members org-id))
  (json-response (hash 'data members)))

(define (handle-invite-member request)
  "POST /orgs/{id}/invite - Invite member to organization"
  (define user (require-auth request))
  (unless user (return (unauthorized-response)))
  
  (define org-id (get-path-param request 'id))
  (unless (user-can-access-org? (hash-ref user 'id) org-id 'admin)
    (return (forbidden-response "Only admins can invite members")))
  
  (define body (parse-json-body request))
  (define email (hash-ref body 'email #f))
  (define role (hash-ref body 'role "member"))
  
  (unless email
    (return (error-response "Email required")))
  
  ;; Check if user exists and add directly, or create invite
  (define invitee (user-find-by-email email))
  (if invitee
      (begin
        (org-add-member! org-id (hash-ref invitee 'id) role #:invited-by (hash-ref user 'id))
        (json-response (hash 'status "added" 'user_id (hash-ref invitee 'id))))
      ;; Would send email invite in production
      (json-response (hash 'status "invited" 'email email))))

;; ============================================================================
;; API Key Management Endpoints
;; ============================================================================

(define (handle-list-api-keys request)
  "GET /api-keys - List user's API keys"
  (define user (require-auth request))
  (unless user (return (unauthorized-response)))
  
  (define keys (api-key-list-for-user (hash-ref user 'id)))
  (json-response (hash 'data keys)))

(define (handle-create-api-key request)
  "POST /api-keys - Create a new API key"
  (define user (require-auth request))
  (unless user (return (unauthorized-response)))
  
  (define body (parse-json-body request))
  (define name (hash-ref body 'name "API Key"))
  
  (define-values (full-key prefix key-hash) (generate-api-key))
  (define key-id (api-key-create! (hash-ref user 'id) name key-hash prefix))
  
  ;; Return the full key only this once
  (json-response 
   (hash 'id key-id
         'key full-key
         'prefix prefix
         'name name
         'message "Store this key securely. It will not be shown again.")
   #:status 201))

(define (handle-delete-api-key request)
  "DELETE /api-keys/{id} - Delete an API key"
  (define user (require-auth request))
  (unless user (return (unauthorized-response)))
  
  (define key-id (get-path-param request 'id))
  (api-key-delete! key-id)
  (json-response (hash 'deleted #t)))

;; ============================================================================
;; BYOK Provider Key Endpoints
;; ============================================================================

(define (handle-list-provider-keys request)
  "GET /provider-keys - List user's provider keys"
  (define user (require-auth request))
  (unless user (return (unauthorized-response)))
  
  (define keys (list-user-keys (hash-ref user 'id)))
  (json-response (hash 'data keys)))

(define (handle-add-provider-key request)
  "POST /provider-keys - Add a provider API key"
  (define user (require-auth request))
  (unless user (return (unauthorized-response)))
  
  (define body (parse-json-body request))
  (define provider (hash-ref body 'provider #f))
  (define api-key (hash-ref body 'api_key #f))
  (define base-url (hash-ref body 'base_url #f))
  (define org-id (hash-ref body 'org_id #f))
  
  (unless (and provider api-key)
    (return (error-response "Provider and api_key required")))
  
  ;; Validate key format
  (define-values (valid? message) (validate-provider-key provider api-key))
  (unless valid?
    (return (error-response message)))
  
  ;; Check org access if org-id provided
  (when org-id
    (unless (user-can-access-org? (hash-ref user 'id) org-id 'admin)
      (return (forbidden-response "Only admins can add org keys"))))
  
  (with-handlers ([exn:fail? (λ (e) (error-response (exn-message e)))])
    (add-user-key! (hash-ref user 'id) provider api-key #:org-id org-id #:base-url base-url)
    (json-response (hash 'status "added" 
                          'provider provider 
                          'hint (get-key-hint api-key))
                   #:status 201)))

(define (handle-delete-provider-key request)
  "DELETE /provider-keys/{provider} - Remove a provider key"
  (define user (require-auth request))
  (unless user (return (unauthorized-response)))
  
  (define provider (get-path-param request 'provider))
  (define org-id (get-query-param request 'org_id))
  
  (remove-user-key! (hash-ref user 'id) provider #:org-id org-id)
  (json-response (hash 'deleted #t)))

;; ============================================================================
;; Session Endpoints
;; ============================================================================

(define (handle-list-sessions request)
  "GET /v1/sessions - List user's sessions"
  (define user (require-auth request))
  (unless user (return (unauthorized-response)))
  
  (define limit (string->number (or (get-query-param request 'limit) "50")))
  (define sessions (session-list-for-user (hash-ref user 'id) #:limit limit))
  (json-response (hash 'data sessions)))

(define (handle-create-session request)
  "POST /v1/sessions - Create a new session"
  (define user (require-auth request))
  (unless user (return (unauthorized-response)))
  
  (define body (parse-json-body request))
  (define mode (hash-ref body 'mode "code"))
  (define title (hash-ref body 'title #f))
  (define org-id (hash-ref body 'org_id #f))
  
  (when org-id
    (unless (user-can-access-org? (hash-ref user 'id) org-id 'write)
      (return (forbidden-response))))
  
  (define session-id (session-create! (hash-ref user 'id) 
                                       #:org-id org-id 
                                       #:mode mode 
                                       #:title title))
  (define session (session-find-by-id session-id))
  (json-response session #:status 201))

(define (handle-get-session request)
  "GET /v1/sessions/{id} - Get session with messages"
  (define user (require-auth request))
  (unless user (return (unauthorized-response)))
  
  (define session-id (get-path-param request 'id))
  (unless (user-can-access-session? (hash-ref user 'id) session-id)
    (return (forbidden-response)))
  
  (define session (session-find-by-id session-id))
  (unless session (return (not-found-response)))
  
  (define messages (session-get-messages session-id))
  (json-response (hash-set session 'messages messages)))

;; ============================================================================
;; OpenAI-Compatible Chat Completions
;; ============================================================================

(define (handle-chat-completions request)
  "POST /v1/chat/completions - OpenAI-compatible chat endpoint"
  (define user (require-auth request))
  (unless user (return (unauthorized-response)))
  
  (define body (parse-json-body request))
  (define model (hash-ref body 'model (config-default-model)))
  (define messages (hash-ref body 'messages '()))
  (define stream (hash-ref body 'stream #f))
  (define session-id (hash-ref body 'session_id #f))
  (define org-id (hash-ref body 'org_id #f))
  
  (unless (and messages (> (length messages) 0))
    (return (error-response "Messages required")))
  
  ;; Determine which provider/key to use
  (define provider (get-model-provider model))
  (define-values (api-key base-url is-byok) 
    (resolve-provider-key (hash-ref user 'id) provider #:org-id org-id))
  
  (unless api-key
    (return (error-response "No API key available for this provider" #:status 400)))
  
  ;; TODO: Actually call the LLM and return response
  ;; This is a placeholder that shows the structure
  (json-response
   (hash 'id (format "chatcmpl-~a" (uuid))
         'object "chat.completion"
         'created (current-seconds)
         'model model
         'choices (list (hash 'index 0
                              'message (hash 'role "assistant"
                                             'content "This is a placeholder response. The actual LLM integration would go here.")
                              'finish_reason "stop"))
         'usage (hash 'prompt_tokens 0
                      'completion_tokens 0
                      'total_tokens 0))))

(define (get-model-provider model)
  "Determine the provider from model name"
  (cond
    [(or (string-prefix? model "gpt-") (string-prefix? model "o1")) "openai"]
    [(string-prefix? model "claude") "anthropic"]
    [(string-prefix? model "gemini") "google"]
    [(string-prefix? model "mistral") "mistral"]
    [else "openai"]))  ; Default to OpenAI

;; ============================================================================
;; Models Endpoint
;; ============================================================================

(define (handle-list-models request)
  "GET /v1/models - List available models"
  (json-response
   (hash 'data (for/list ([model (config-allowed-models)])
                 (hash 'id model
                       'object "model"
                       'owned_by "chrysalis-forge")))))

;; ============================================================================
;; Health Check
;; ============================================================================

(define (handle-health request)
  "GET /health - Health check endpoint"
  (json-response (hash 'status "ok" 
                        'version "1.0.0"
                        'timestamp (current-seconds))))

;; ============================================================================
;; Router
;; ============================================================================

(define (route-request request)
  "Main router - dispatch request to handler"
  (define method (hash-ref request 'method "GET"))
  (define path (hash-ref request 'path "/"))
  
  (define (match-route m p)
    (and (equal? method m) (route-matches? p path)))
  
  (with-handlers ([hash? (λ (r) r)]  ; Return response if raised
                  [exn:fail? (λ (e) (error-response (exn-message e) #:status 500))])
    (cond
      ;; Health
      [(match-route "GET" "/health") (handle-health request)]
      
      ;; Auth
      [(match-route "POST" "/auth/register") (handle-register request)]
      [(match-route "POST" "/auth/login") (handle-login request)]
      [(match-route "GET" "/users/me") (handle-me request)]
      
      ;; Organizations
      [(match-route "GET" "/orgs") (handle-list-orgs request)]
      [(match-route "POST" "/orgs") (handle-create-org request)]
      [(route-matches? "/orgs/:id" path)
       (let ([request (hash-set request 'path-params 
                                (extract-path-params "/orgs/:id" path))])
         (match method
           ["GET" (handle-get-org request)]
           [_ (error-response "Method not allowed" #:status 405)]))]
      [(route-matches? "/orgs/:id/members" path)
       (let ([request (hash-set request 'path-params 
                                (extract-path-params "/orgs/:id/members" path))])
         (match method
           ["GET" (handle-list-org-members request)]
           [_ (error-response "Method not allowed" #:status 405)]))]
      [(route-matches? "/orgs/:id/invite" path)
       (let ([request (hash-set request 'path-params 
                                (extract-path-params "/orgs/:id/invite" path))])
         (match method
           ["POST" (handle-invite-member request)]
           [_ (error-response "Method not allowed" #:status 405)]))]
      
      ;; API Keys
      [(match-route "GET" "/api-keys") (handle-list-api-keys request)]
      [(match-route "POST" "/api-keys") (handle-create-api-key request)]
      [(route-matches? "/api-keys/:id" path)
       (let ([request (hash-set request 'path-params 
                                (extract-path-params "/api-keys/:id" path))])
         (match method
           ["DELETE" (handle-delete-api-key request)]
           [_ (error-response "Method not allowed" #:status 405)]))]
      
      ;; Provider Keys (BYOK)
      [(match-route "GET" "/provider-keys") (handle-list-provider-keys request)]
      [(match-route "POST" "/provider-keys") (handle-add-provider-key request)]
      [(route-matches? "/provider-keys/:provider" path)
       (let ([request (hash-set request 'path-params 
                                (extract-path-params "/provider-keys/:provider" path))])
         (match method
           ["DELETE" (handle-delete-provider-key request)]
           [_ (error-response "Method not allowed" #:status 405)]))]
      
      ;; Sessions
      [(match-route "GET" "/v1/sessions") (handle-list-sessions request)]
      [(match-route "POST" "/v1/sessions") (handle-create-session request)]
      [(route-matches? "/v1/sessions/:id" path)
       (let ([request (hash-set request 'path-params 
                                (extract-path-params "/v1/sessions/:id" path))])
         (match method
           ["GET" (handle-get-session request)]
           [_ (error-response "Method not allowed" #:status 405)]))]
      
      ;; OpenAI-compatible endpoints
      [(match-route "POST" "/v1/chat/completions") (handle-chat-completions request)]
      [(match-route "GET" "/v1/models") (handle-list-models request)]
      
      ;; Not found
      [else (not-found-response)])))

;; ============================================================================
;; Route Matching Helpers
;; ============================================================================

(define (route-matches? pattern path)
  "Check if a path matches a route pattern with :params"
  (define pattern-parts (filter (λ (s) (> (string-length s) 0)) 
                                (string-split pattern "/")))
  (define path-parts (filter (λ (s) (> (string-length s) 0)) 
                             (string-split path "/")))
  
  (and (= (length pattern-parts) (length path-parts))
       (for/and ([pp pattern-parts] [pa path-parts])
         (or (string-prefix? pp ":") (equal? pp pa)))))

(define (extract-path-params pattern path)
  "Extract path parameters from a matched route"
  (define pattern-parts (filter (λ (s) (> (string-length s) 0)) 
                                (string-split pattern "/")))
  (define path-parts (filter (λ (s) (> (string-length s) 0)) 
                             (string-split path "/")))
  
  (for/hash ([pp pattern-parts] [pa path-parts]
             #:when (string-prefix? pp ":"))
    (values (string->symbol (substring pp 1)) pa)))

;; Return helper macro
(define-syntax-rule (return val)
  (raise val))
