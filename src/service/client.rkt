#lang racket/base
;; Chrysalis Forge Service Client
;; Connect to a running Chrysalis service and forward requests

(provide (all-defined-out))

(require racket/string racket/match json racket/port net/http-client net/url racket/tcp)

;; ============================================================================
;; Client Configuration
;; ============================================================================

(define DEFAULT-SERVICE-URL "http://127.0.0.1:8080")

(struct ServiceClient (host port api-key session-id) #:transparent #:mutable)

(define current-client (make-parameter #f))

(define (parse-service-url url-string)
  "Parse a service URL into host and port"
  (define url (if (string-contains? url-string "://")
                  url-string
                  (string-append "http://" url-string)))
  (define parsed (string->url url))
  (values (url-host parsed) 
          (or (url-port parsed) 8080)))

;; ============================================================================
;; HTTP Client Helpers
;; ============================================================================

(define (service-request client method path #:body [body #f] #:headers [extra-headers '()])
  "Make an HTTP request to the service"
  (define host (ServiceClient-host client))
  (define port (ServiceClient-port client))
  (define api-key (ServiceClient-api-key client))
  
  (define headers
    (append (list "Content-Type: application/json")
            (if api-key 
                (list (format "Authorization: Bearer ~a" api-key))
                '())
            extra-headers))
  
  (define body-bytes
    (if body (string->bytes/utf-8 (jsexpr->string body)) #f))
  
  (define-values (status response-headers in)
    (http-sendrecv host
                   path
                   #:port port
                   #:ssl? #f
                   #:method method
                   #:headers headers
                   #:data body-bytes))
  
  (define response-body (port->string in))
  (close-input-port in)
  
  (define response-json
    (with-handlers ([exn:fail? (λ (_) (hash 'raw response-body))])
      (string->jsexpr response-body)))
  
  (values (bytes->string/utf-8 status) response-json))

;; ============================================================================
;; Client Connection
;; ============================================================================

(define (connect-service! url-string #:api-key [api-key #f])
  "Connect to a running Chrysalis service"
  (define-values (host port) (parse-service-url url-string))
  
  (eprintf "[CLIENT] Connecting to ~a:~a...~n" host port)
  
  ;; Test connection with health check
  (define client (ServiceClient host port api-key #f))
  
  (with-handlers ([exn:fail? (λ (e)
                               (eprintf "[CLIENT] Connection failed: ~a~n" (exn-message e))
                               #f)])
    (define-values (status response) (service-request client "GET" "/health"))
    
    (if (string-prefix? status "2")
        (begin
          (eprintf "[CLIENT] Connected! Service version: ~a~n" 
                   (hash-ref response 'version "unknown"))
          (current-client client)
          client)
        (begin
          (eprintf "[CLIENT] Service responded with error: ~a~n" status)
          #f))))

(define (disconnect-service!)
  "Disconnect from the service"
  (current-client #f))

;; ============================================================================
;; Authentication
;; ============================================================================

(define (client-login! email password)
  "Login to the service and store the token"
  (define client (current-client))
  (unless client (error 'client-login! "Not connected to service"))
  
  (define-values (status response)
    (service-request client "POST" "/auth/login"
                     #:body (hash 'email email 'password password)))
  
  (if (string-prefix? status "2")
      (begin
        (set-ServiceClient-api-key! client (hash-ref response 'token))
        (eprintf "[CLIENT] Logged in as ~a~n" (hash-ref response 'email "user"))
        #t)
      (begin
        (eprintf "[CLIENT] Login failed: ~a~n" (hash-ref response 'error (hash 'message "Unknown error")))
        #f)))

(define (client-register! email password #:display-name [display-name #f])
  "Register a new account on the service"
  (define client (current-client))
  (unless client (error 'client-register! "Not connected to service"))
  
  (define-values (status response)
    (service-request client "POST" "/auth/register"
                     #:body (hash 'email email 
                                  'password password
                                  'display_name display-name)))
  
  (if (string-prefix? status "2")
      (begin
        (set-ServiceClient-api-key! client (hash-ref response 'token))
        (eprintf "[CLIENT] Registered and logged in as ~a~n" email)
        #t)
      (begin
        (eprintf "[CLIENT] Registration failed: ~a~n" 
                 (hash-ref (hash-ref response 'error (hash)) 'message "Unknown error"))
        #f)))

;; ============================================================================
;; Session Management
;; ============================================================================

(define (client-create-session! #:mode [mode "code"] #:title [title #f])
  "Create a new session on the service"
  (define client (current-client))
  (unless client (error 'client-create-session! "Not connected to service"))
  
  (define-values (status response)
    (service-request client "POST" "/v1/sessions"
                     #:body (hash 'mode mode 'title title)))
  
  (if (string-prefix? status "2")
      (let ([session-id (hash-ref response 'id)])
        (set-ServiceClient-session-id! client session-id)
        (eprintf "[CLIENT] Session created: ~a~n" session-id)
        session-id)
      (begin
        (eprintf "[CLIENT] Session creation failed: ~a~n" response)
        #f)))

(define (client-list-sessions #:limit [limit 10])
  "List recent sessions"
  (define client (current-client))
  (unless client (error 'client-list-sessions "Not connected to service"))
  
  (define-values (status response)
    (service-request client "GET" (format "/v1/sessions?limit=~a" limit)))
  
  (if (string-prefix? status "2")
      (hash-ref response 'data '())
      '()))

;; ============================================================================
;; Chat Completions (Main Interface)
;; ============================================================================

(define (client-chat message #:model [model #f] #:stream [stream #f])
  "Send a chat message to the service and get a response"
  (define client (current-client))
  (unless client (error 'client-chat "Not connected to service"))
  
  (define body
    (hash 'messages (list (hash 'role "user" 'content message))
          'model (or model "gpt-5.2")
          'stream stream
          'session_id (ServiceClient-session-id client)))
  
  (define-values (status response)
    (service-request client "POST" "/v1/chat/completions" #:body body))
  
  (if (string-prefix? status "2")
      (let* ([choices (hash-ref response 'choices '())]
             [first-choice (if (null? choices) #f (car choices))]
             [message (and first-choice (hash-ref first-choice 'message #f))]
             [content (and message (hash-ref message 'content ""))])
        content)
      (begin
        (eprintf "[CLIENT] Chat failed: ~a~n" 
                 (hash-ref (hash-ref response 'error (hash)) 'message "Unknown error"))
        #f)))

;; ============================================================================
;; Service Info
;; ============================================================================

(define (client-get-models)
  "Get list of available models from the service"
  (define client (current-client))
  (unless client (error 'client-get-models "Not connected to service"))
  
  (define-values (status response)
    (service-request client "GET" "/v1/models"))
  
  (if (string-prefix? status "2")
      (for/list ([m (hash-ref response 'data '())])
        (hash-ref m 'id))
      '()))

(define (client-get-user)
  "Get current user info"
  (define client (current-client))
  (unless client (error 'client-get-user "Not connected to service"))
  
  (define-values (status response)
    (service-request client "GET" "/users/me"))
  
  (if (string-prefix? status "2")
      response
      #f))

;; ============================================================================
;; Interactive Client REPL
;; ============================================================================

(define (client-repl url-string #:api-key [api-key #f])
  "Run an interactive REPL connected to the service"
  
  ;; Connect to service
  (define client (connect-service! url-string #:api-key api-key))
  (unless client
    (eprintf "[CLIENT] Failed to connect to ~a~n" url-string)
    (exit 1))
  
  ;; If no API key, prompt for login
  (unless (ServiceClient-api-key client)
    (eprintf "~n[CLIENT] Authentication required.~n")
    (eprintf "Enter 'login' to login or 'register' to create an account.~n~n")
    (let auth-loop ()
      (display "auth> ")
      (flush-output)
      (define input (read-line))
      (cond
        [(eof-object? input) (exit 0)]
        [(equal? (string-trim input) "login")
         (display "Email: ") (flush-output)
         (define email (read-line))
         (display "Password: ") (flush-output)
         (define password (read-line))
         (unless (client-login! email password)
           (auth-loop))]
        [(equal? (string-trim input) "register")
         (display "Email: ") (flush-output)
         (define email (read-line))
         (display "Password: ") (flush-output)
         (define password (read-line))
         (display "Display Name (optional): ") (flush-output)
         (define name (read-line))
         (unless (client-register! email password 
                                   #:display-name (if (equal? name "") #f name))
           (auth-loop))]
        [else
         (eprintf "Unknown command. Enter 'login' or 'register'.~n")
         (auth-loop)])))
  
  ;; Create a session
  (client-create-session! #:mode "code")
  
  ;; Print help
  (eprintf "~n========================================~n")
  (eprintf "  Chrysalis Forge Client~n")
  (eprintf "  Connected to: ~a:~a~n" 
           (ServiceClient-host client) (ServiceClient-port client))
  (eprintf "========================================~n")
  (eprintf "Commands: /quit, /models, /sessions, /help~n")
  (eprintf "Type your message to chat with the agent.~n~n")
  
  ;; Main REPL loop
  (let loop ()
    (display ">>> ")
    (flush-output)
    (define input (read-line))
    (cond
      [(eof-object? input) 
       (eprintf "~n[CLIENT] Goodbye!~n")]
      [(equal? (string-trim input) "")
       (loop)]
      [(string-prefix? (string-trim input) "/")
       ;; Handle commands
       (define cmd (string-trim input))
       (match cmd
         ["/quit" (eprintf "[CLIENT] Goodbye!~n")]
         ["/exit" (eprintf "[CLIENT] Goodbye!~n")]
         ["/models" 
          (define models (client-get-models))
          (eprintf "Available models: ~a~n" (string-join models ", "))
          (loop)]
         ["/sessions"
          (define sessions (client-list-sessions))
          (for ([s sessions])
            (eprintf "  ~a: ~a (~a)~n" 
                     (hash-ref s 'id "?")
                     (or (hash-ref s 'title #f) "(untitled)")
                     (hash-ref s 'mode "?")))
          (loop)]
         ["/help"
          (eprintf "Commands:~n")
          (eprintf "  /quit     - Exit the client~n")
          (eprintf "  /models   - List available models~n")
          (eprintf "  /sessions - List your sessions~n")
          (eprintf "  /help     - Show this help~n")
          (loop)]
         [_
          (eprintf "Unknown command: ~a~n" cmd)
          (loop)])]
      [else
       ;; Send message to agent
       (define response (client-chat input))
       (when response
         (displayln response))
       (newline)
       (loop)])))
