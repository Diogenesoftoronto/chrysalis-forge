#lang racket/base
;; Chrysalis Forge API Router
;; RESTful API routes with OpenAI-compatible endpoints

(provide (all-defined-out))

(require racket/string racket/match json racket/port racket/date racket/list net/http-client net/url)
(require "config.rkt" "db.rkt" "auth.rkt" (except-in "key-vault.rkt" sha256-bytes))
(require "../llm/model-registry.rkt" "../llm/openai-client.rkt")
(require "../core/thread-manager.rkt")

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
;; Thread Endpoints (User-Facing Abstraction)
;; ============================================================================

(define (handle-list-threads request)
  "GET /v1/threads - List user's threads"
  (define user (require-auth request))
  (unless user (return (unauthorized-response)))
  
  (define limit (string->number (or (get-query-param request 'limit) "50")))
  (define project-id (get-query-param request 'project_id))
  (define status (get-query-param request 'status))
  
  (define threads (thread-list-for-user (hash-ref user 'id) 
                                         #:project-id project-id 
                                         #:status status
                                         #:limit limit))
  (json-response (hash 'data threads)))

(define (handle-create-thread request)
  "POST /v1/threads - Create a new thread"
  (define user (require-auth request))
  (unless user (return (unauthorized-response)))
  
  (define body (parse-json-body request))
  (define title (hash-ref body 'title #f))
  (define project-id (hash-ref body 'project_id #f))
  (define org-id (hash-ref body 'org_id #f))
  (define parent-thread-id (hash-ref body 'parent_thread_id #f))
  (define continues-from (hash-ref body 'continues_from #f))
  
  (when org-id
    (unless (user-can-access-org? (hash-ref user 'id) org-id 'write)
      (return (forbidden-response))))
  
  (define thread
    (cond
      [continues-from
       (thread-continue (hash-ref user 'id) continues-from 
                        #:title title #:project-id project-id)]
      [parent-thread-id
       (thread-spawn-child (hash-ref user 'id) parent-thread-id title 
                           #:project-id project-id)]
      [else
       (ensure-thread (hash-ref user 'id) 
                      #:project-id project-id 
                      #:title title)]))
  
  (json-response thread #:status 201))

(define (handle-get-thread request)
  "GET /v1/threads/{id} - Get thread details with relations"
  (define user (require-auth request))
  (unless user (return (unauthorized-response)))
  
  (define thread-id (get-path-param request 'id))
  (define thread (thread-find-by-id thread-id))
  (unless thread (return (not-found-response)))
  
  (unless (equal? (hash-ref thread 'user_id) (hash-ref user 'id))
    (return (forbidden-response)))
  
  (define relations (thread-get-related thread-id))
  (define contexts (thread-context-tree thread-id))
  
  (json-response (hash-set (hash-set thread 'relations relations) 
                           'contexts contexts)))

(define (handle-update-thread request)
  "PATCH /v1/threads/{id} - Update thread"
  (define user (require-auth request))
  (unless user (return (unauthorized-response)))
  
  (define thread-id (get-path-param request 'id))
  (define thread (thread-find-by-id thread-id))
  (unless thread (return (not-found-response)))
  
  (unless (equal? (hash-ref thread 'user_id) (hash-ref user 'id))
    (return (forbidden-response)))
  
  (define body (parse-json-body request))
  (thread-update! thread-id
                  #:title (hash-ref body 'title #f)
                  #:status (hash-ref body 'status #f)
                  #:summary (hash-ref body 'summary #f))
  
  (json-response (thread-find-by-id thread-id)))

(define (handle-thread-chat request)
  "POST /v1/threads/{id}/messages - Chat on a thread"
  (define user (require-auth request))
  (unless user (return (unauthorized-response)))
  
  (define thread-id (get-path-param request 'id))
  (define thread (thread-find-by-id thread-id))
  (unless thread (return (not-found-response)))
  
  (unless (equal? (hash-ref thread 'user_id) (hash-ref user 'id))
    (return (forbidden-response)))
  
  (define body (parse-json-body request))
  (define prompt (hash-ref body 'content #f))
  (define mode (hash-ref body 'mode "code"))
  (define context-node-id (hash-ref body 'context_node_id #f))
  
  (unless prompt
    (return (error-response "Message content required")))
  
  ;; Prepare for chat (gets/creates session, checks rotation)
  (define prep (thread-chat-prepare (hash-ref user 'id) prompt
                                    #:thread-id thread-id
                                    #:mode mode
                                    #:context-node-id context-node-id))
  
  ;; Invoke LLM with the prepared context
  (define api-key (hash-ref user 'api_key #f))
  (define llm-sender (make-openai-sender #:api-key api-key))
  (define context-messages (hash-ref prep 'context '()))
  (define full-prompt (append context-messages (list (hash 'role "user" 'content prompt))))
  (define-values (success? response metadata) (llm-sender full-prompt))
  
  (if success?
      (json-response 
       (hash 'thread_id thread-id
             'session_id (hash-ref prep 'session_id)
             'message response
             'usage (hash 'prompt_tokens (hash-ref metadata 'prompt_tokens 0)
                          'completion_tokens (hash-ref metadata 'completion_tokens 0)
                          'total_tokens (hash-ref metadata 'total_tokens 0))))
      (json-response 
       (hash 'error (hash 'message response 'type "llm_error"))
       #:status 500)))

(define (handle-create-thread-relation request)
  "POST /v1/threads/{id}/relations - Create thread relation"
  (define user (require-auth request))
  (unless user (return (unauthorized-response)))
  
  (define from-thread-id (get-path-param request 'id))
  (define from-thread (thread-find-by-id from-thread-id))
  (unless from-thread (return (not-found-response)))
  
  (unless (equal? (hash-ref from-thread 'user_id) (hash-ref user 'id))
    (return (forbidden-response)))
  
  (define body (parse-json-body request))
  (define to-thread-id (hash-ref body 'to_thread_id #f))
  (define relation-type (hash-ref body 'relation_type "relates_to"))
  
  (unless to-thread-id
    (return (error-response "to_thread_id required")))
  
  (unless (member relation-type '("continues_from" "child_of" "relates_to"))
    (return (error-response "Invalid relation_type")))
  
  (define rel-id (thread-link! from-thread-id to-thread-id (hash-ref user 'id) 
                               #:type relation-type))
  (json-response (hash 'id rel-id 
                       'from_thread_id from-thread-id 
                       'to_thread_id to-thread-id 
                       'relation_type relation-type) 
                 #:status 201))

(define (handle-list-thread-contexts request)
  "GET /v1/threads/{id}/contexts - Get thread context hierarchy"
  (define user (require-auth request))
  (unless user (return (unauthorized-response)))
  
  (define thread-id (get-path-param request 'id))
  (define thread (thread-find-by-id thread-id))
  (unless thread (return (not-found-response)))
  
  (unless (equal? (hash-ref thread 'user_id) (hash-ref user 'id))
    (return (forbidden-response)))
  
  (json-response (hash 'data (thread-context-tree thread-id))))

(define (handle-create-thread-context request)
  "POST /v1/threads/{id}/contexts - Add context node"
  (define user (require-auth request))
  (unless user (return (unauthorized-response)))
  
  (define thread-id (get-path-param request 'id))
  (define thread (thread-find-by-id thread-id))
  (unless thread (return (not-found-response)))
  
  (unless (equal? (hash-ref thread 'user_id) (hash-ref user 'id))
    (return (forbidden-response)))
  
  (define body (parse-json-body request))
  (define title (hash-ref body 'title #f))
  (define parent-id (hash-ref body 'parent_id #f))
  (define kind (hash-ref body 'kind "note"))
  (define body-text (hash-ref body 'body #f))
  
  (unless title
    (return (error-response "Title required")))
  
  (define ctx-id (thread-add-context! thread-id title
                                       #:parent-id parent-id
                                       #:kind kind
                                       #:body body-text))
  (json-response (thread-context-find-by-id ctx-id) #:status 201))

;; ============================================================================
;; Project Endpoints
;; ============================================================================

(define (handle-list-projects request)
  "GET /v1/projects - List user's projects"
  (define user (require-auth request))
  (unless user (return (unauthorized-response)))
  
  (define limit (string->number (or (get-query-param request 'limit) "50")))
  (define org-id (get-query-param request 'org_id))
  
  (define projects (project-list-for-user (hash-ref user 'id) 
                                           #:org-id org-id 
                                           #:limit limit))
  (json-response (hash 'data projects)))

(define (handle-create-project request)
  "POST /v1/projects - Create a new project"
  (define user (require-auth request))
  (unless user (return (unauthorized-response)))
  
  (define body (parse-json-body request))
  (define name (hash-ref body 'name #f))
  (define slug (hash-ref body 'slug #f))
  (define description (hash-ref body 'description #f))
  (define org-id (hash-ref body 'org_id #f))
  
  (unless name
    (return (error-response "Project name required")))
  
  (when org-id
    (unless (user-can-access-org? (hash-ref user 'id) org-id 'write)
      (return (forbidden-response))))
  
  (define project-id (project-create! (hash-ref user 'id) name
                                       #:org-id org-id
                                       #:slug slug
                                       #:description description))
  (json-response (project-find-by-id project-id) #:status 201))

(define (handle-get-project request)
  "GET /v1/projects/{id} - Get project details"
  (define user (require-auth request))
  (unless user (return (unauthorized-response)))
  
  (define project-id (get-path-param request 'id))
  (define project (project-find-by-id project-id))
  (unless project (return (not-found-response)))
  
  (unless (equal? (hash-ref project 'owner_id) (hash-ref user 'id))
    (return (forbidden-response)))
  
  ;; Include threads for this project
  (define threads (thread-list-for-user (hash-ref user 'id) 
                                         #:project-id project-id))
  (json-response (hash-set project 'threads threads)))

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
  "GET /v1/models - List available models from OpenAI"
  (with-handlers ([exn:fail? (λ (e) 
                               (error-response (format "Failed to fetch models: ~a" (exn-message e)) 
                                               #:status 500))])
    ;; Get OpenAI API key and base URL
    (define api-key (get-service-key "openai"))
    (define base-url (get-service-base-url "openai"))
    
    (unless api-key
      (return (error-response "OpenAI API key not configured. Set OPENAI_API_KEY environment variable." 
                              #:status 500)))
    
    ;; Fetch models from OpenAI endpoint
    (define models (fetch-models-from-endpoint base-url api-key))
    
    ;; Return in OpenAI-compatible format
    (json-response
     (hash 'data (if (and (list? models) (> (length models) 0))
                      models
                      ;; Fallback to config if fetch fails or returns empty
                      (for/list ([model (config-allowed-models)])
                        (hash 'id model
                              'object "model"
                              'owned_by "chrysalis-forge")))))))

(define (handle-get-model request)
  "GET /api/models/{model_name} - Get details for a specific model"
  (with-handlers ([exn:fail? (λ (e) 
                               (error-response (format "Failed to fetch model: ~a" (exn-message e)) 
                                               #:status 500))])
    (define model-name (get-path-param request 'model_name))
    (unless model-name
      (return (error-response "Model name required" #:status 400)))
    
    ;; Get API key and base URL - try to detect provider from base URL
    (define base-url (get-service-base-url "openai"))
    (define api-key (get-service-key "openai"))
    
    ;; Check if base URL contains backboard.io or other providers
    (define provider
      (cond
        [(string-contains? (or base-url "") "backboard.io") "backboard"]
        [(string-contains? (or base-url "") "openrouter.ai") "openrouter"]
        [else "openai"]))
    
    (define actual-base-url (or base-url "https://api.openai.com/v1"))
    (define actual-api-key (or api-key (getenv "OPENAI_API_KEY")))
    
    (unless actual-api-key
      (return (error-response "API key not configured" #:status 500)))
    
    ;; Build the URL for fetching a specific model
    ;; Clean trailing slash and remove /api if present (we'll add it back for backboard)
    (define clean-base 
      (let ([no-trailing (if (string-suffix? actual-base-url "/")
                              (substring actual-base-url 0 (sub1 (string-length actual-base-url)))
                              actual-base-url)])
        ;; For backboard, remove /api if present since we'll add /api/models
        (if (and (equal? provider "backboard") (string-suffix? no-trailing "/api"))
            (substring no-trailing 0 (- (string-length no-trailing) 4))
            no-trailing)))
    
    ;; Always append /api/models for backboard, /models for others
    (define model-url
      (if (equal? provider "backboard")
          (format "~a/api/models/~a" clean-base model-name)
          (format "~a/models/~a" clean-base model-name)))
    
    (define parsed-url (string->url model-url))
    (define host (url-host parsed-url))
    (define port (or (url-port parsed-url) (if (equal? (url-scheme parsed-url) "https") 443 80)))
    (define path-segments (url-path parsed-url))
    (define path-part (if (null? path-segments)
                          (format "/models/~a" model-name)
                          (string-append "/" (string-join (map path/param-path path-segments) "/"))))
    
    ;; Use appropriate header format based on provider
    (define auth-header
      (if (equal? provider "backboard")
          (format "X-API-Key: ~a" actual-api-key)
          (format "Authorization: Bearer ~a" actual-api-key)))
    
    (define request-headers (list auth-header
                                 "Content-Type: application/json"))
    
    (define-values (status headers in)
      (http-sendrecv host path-part
                     #:port port
                     #:ssl? (equal? (url-scheme parsed-url) "https")
                     #:method "GET"
                     #:headers request-headers))
    
    (define status-str (bytes->string/utf-8 status))
    (define response-body (port->string in))
    (close-input-port in)
    
    (unless (string-prefix? status-str "HTTP/1.1 200")
      (return (error-response (format "Failed to fetch model: HTTP ~a" status-str) 
                              #:status (if (string-contains? status-str "404") 404 500))))
    
    (define response (with-handlers ([exn:fail? (λ (e)
                                                   (error (format "Failed to parse response: ~a" (exn-message e))))])
                       (string->jsexpr response-body)))
    
    (json-response response)))

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
      
      ;; Sessions (internal - prefer threads)
      [(match-route "GET" "/v1/sessions") (handle-list-sessions request)]
      [(match-route "POST" "/v1/sessions") (handle-create-session request)]
      [(route-matches? "/v1/sessions/:id" path)
       (let ([request (hash-set request 'path-params 
                                (extract-path-params "/v1/sessions/:id" path))])
         (match method
           ["GET" (handle-get-session request)]
           [_ (error-response "Method not allowed" #:status 405)]))]
      
      ;; Threads (user-facing)
      [(match-route "GET" "/v1/threads") (handle-list-threads request)]
      [(match-route "POST" "/v1/threads") (handle-create-thread request)]
      [(route-matches? "/v1/threads/:id/messages" path)
       (let ([request (hash-set request 'path-params 
                                (extract-path-params "/v1/threads/:id/messages" path))])
         (match method
           ["POST" (handle-thread-chat request)]
           [_ (error-response "Method not allowed" #:status 405)]))]
      [(route-matches? "/v1/threads/:id/relations" path)
       (let ([request (hash-set request 'path-params 
                                (extract-path-params "/v1/threads/:id/relations" path))])
         (match method
           ["POST" (handle-create-thread-relation request)]
           [_ (error-response "Method not allowed" #:status 405)]))]
      [(route-matches? "/v1/threads/:id/contexts" path)
       (let ([request (hash-set request 'path-params 
                                (extract-path-params "/v1/threads/:id/contexts" path))])
         (match method
           ["GET" (handle-list-thread-contexts request)]
           ["POST" (handle-create-thread-context request)]
           [_ (error-response "Method not allowed" #:status 405)]))]
      [(route-matches? "/v1/threads/:id" path)
       (let ([request (hash-set request 'path-params 
                                (extract-path-params "/v1/threads/:id" path))])
         (match method
           ["GET" (handle-get-thread request)]
           ["PATCH" (handle-update-thread request)]
           [_ (error-response "Method not allowed" #:status 405)]))]
      
      ;; Projects
      [(match-route "GET" "/v1/projects") (handle-list-projects request)]
      [(match-route "POST" "/v1/projects") (handle-create-project request)]
      [(route-matches? "/v1/projects/:id" path)
       (let ([request (hash-set request 'path-params 
                                (extract-path-params "/v1/projects/:id" path))])
         (match method
           ["GET" (handle-get-project request)]
           [_ (error-response "Method not allowed" #:status 405)]))]
      
      ;; OpenAI-compatible endpoints
      [(match-route "POST" "/v1/chat/completions") (handle-chat-completions request)]
      [(match-route "GET" "/v1/models") (handle-list-models request)]
      [(route-matches? "/api/models/:model_name" path)
       (let ([request (hash-set request 'path-params 
                                (extract-path-params "/api/models/:model_name" path))])
         (match method
           ["GET" (handle-get-model request)]
           [_ (error-response "Method not allowed" #:status 405)]))]
      
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
