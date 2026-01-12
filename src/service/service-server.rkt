#lang racket/base
;; Chrysalis Forge HTTP/WebSocket Service Server
;; Main server entry point with CORS, request handling, and WebSocket support

(provide (all-defined-out))

(require racket/string racket/match racket/port json
         web-server/servlet
         web-server/servlet-env
         web-server/http/request-structs
         web-server/http/response-structs
         web-server/http/bindings
         net/url)

(require "config.rkt" "db.rkt" "api-router.rkt")

;; ============================================================================
;; Request Processing
;; ============================================================================

(define (request->hash req)
  "Convert a web-server request to our internal hash format"
  (define method (bytes->string/utf-8 (request-method req)))
  (define uri (request-uri req))
  (define path (path->string (url-path->string (url-path uri))))
  (define query-string (url-query uri))
  
  ;; Parse headers
  (define headers
    (for/hash ([h (request-headers/raw req)])
      (values (string->symbol (string-downcase (bytes->string/utf-8 (header-field h))))
              (bytes->string/utf-8 (header-value h)))))
  
  ;; Parse query params
  (define query
    (for/hash ([q query-string])
      (values (string->symbol (car q)) (cdr q))))
  
  ;; Parse body
  (define body
    (let ([bindings (request-bindings/raw req)])
      (if (and bindings (pair? bindings))
          (bytes->string/utf-8 (binding:form-value (first bindings)))
          (let ([post-data (request-post-data/raw req)])
            (if post-data (bytes->string/utf-8 post-data) "")))))
  
  (hash 'method method
        'path path
        'query query
        'headers headers
        'body body
        'raw-request req))

(define (hash->response resp)
  "Convert our internal response hash to web-server response"
  (define status (hash-ref resp 'status 200))
  (define headers-list (hash-ref resp 'headers '()))
  (define body (hash-ref resp 'body ""))
  
  (response/full
   status
   (status-code->message status)
   (current-seconds)
   #"application/json; charset=utf-8"
   (for/list ([h headers-list])
     (header (string->bytes/utf-8 (symbol->string (car h)))
             (string->bytes/utf-8 (cdr h))))
   (list (string->bytes/utf-8 body))))

(define (status-code->message code)
  (match code
    [200 #"OK"]
    [201 #"Created"]
    [204 #"No Content"]
    [400 #"Bad Request"]
    [401 #"Unauthorized"]
    [403 #"Forbidden"]
    [404 #"Not Found"]
    [405 #"Method Not Allowed"]
    [429 #"Too Many Requests"]
    [500 #"Internal Server Error"]
    [_ #"Unknown"]))

;; ============================================================================
;; CORS Handling
;; ============================================================================

(define (add-cors-headers response allowed-origins)
  "Add CORS headers to response"
  (define existing-headers (hash-ref response 'headers '()))
  (define cors-headers
    (list (cons 'access-control-allow-origin 
                (if (equal? allowed-origins '("*")) "*" 
                    (string-join allowed-origins ", ")))
          (cons 'access-control-allow-methods "GET, POST, PUT, DELETE, OPTIONS")
          (cons 'access-control-allow-headers "Content-Type, Authorization, X-API-Key")
          (cons 'access-control-max-age "86400")))
  (hash-set response 'headers (append existing-headers cors-headers)))

(define (handle-options-request request config)
  "Handle CORS preflight requests"
  (define allowed-origins (SecurityConfig-allowed-origins 
                           (ServiceConfig-security config)))
  (add-cors-headers (hash 'status 204 'headers '() 'body "") allowed-origins))

;; ============================================================================
;; Main Servlet
;; ============================================================================

(define (make-service-servlet config)
  "Create the main servlet handler"
  (define allowed-origins (SecurityConfig-allowed-origins 
                           (ServiceConfig-security config)))
  
  (lambda (req)
    (define request-hash (request->hash req))
    (define method (hash-ref request-hash 'method))
    
    ;; Handle CORS preflight
    (if (equal? method "OPTIONS")
        (hash->response (handle-options-request request-hash config))
        ;; Route the request
        (let ([response (route-request request-hash)])
          (hash->response (add-cors-headers response allowed-origins))))))

;; ============================================================================
;; Server Lifecycle
;; ============================================================================

(define current-server-thread (make-parameter #f))
(define current-server-shutdown (make-parameter #f))

(define (start-service! #:config [config #f] #:port [port #f] #:host [host #f])
  "Start the HTTP service"
  (define cfg (or config (get-config)))
  (define server-port (or port (ServerConfig-port (ServiceConfig-server cfg))))
  (define server-host (or host (ServerConfig-host (ServiceConfig-server cfg))))
  
  ;; Initialize database
  (init-database!)
  
  (eprintf "~n========================================~n")
  (eprintf "   Chrysalis Forge Service~n")
  (eprintf "========================================~n")
  (eprintf "Listening on http://~a:~a~n" server-host server-port)
  (eprintf "Database: ~a~n" (config-database-url))
  (eprintf "Default model: ~a~n" (config-default-model))
  (eprintf "========================================~n~n")
  
  ;; Start server
  (define stop-server
    (serve/servlet
     (make-service-servlet cfg)
     #:port server-port
     #:listen-ip server-host
     #:servlet-path "/"
     #:servlet-regexp #rx""
     #:command-line? #t
     #:launch-browser? #f
     #:log-file (build-path (find-system-path 'home-dir) ".chrysalis" "service.log")))
  
  (current-server-shutdown stop-server)
  stop-server)

(define (stop-service!)
  "Stop the HTTP service"
  (when (current-server-shutdown)
    ((current-server-shutdown))
    (current-server-shutdown #f))
  (close-database!))

;; ============================================================================
;; Daemon Mode
;; ============================================================================

(define (write-pid-file!)
  "Write PID file for daemon mode"
  (define pid-path (build-path (find-system-path 'home-dir) ".chrysalis" "chrysalis.pid"))
  (make-directory* (path-only pid-path))
  (call-with-output-file pid-path
    (λ (out) (write (current-process-id) out))
    #:exists 'truncate/replace)
  pid-path)

(define (read-pid-file)
  "Read PID from file"
  (define pid-path (build-path (find-system-path 'home-dir) ".chrysalis" "chrysalis.pid"))
  (if (file-exists? pid-path)
      (call-with-input-file pid-path read)
      #f))

(define (remove-pid-file!)
  "Remove PID file"
  (define pid-path (build-path (find-system-path 'home-dir) ".chrysalis" "chrysalis.pid"))
  (when (file-exists? pid-path)
    (delete-file pid-path)))

(define (daemonize! thunk)
  "Run thunk in daemon mode (double-fork pattern on Unix)"
  ;; Simple approach: just run in background
  ;; Full daemonization would require C FFI for fork()
  (define pid-path (write-pid-file!))
  (eprintf "[DAEMON] PID file: ~a~n" pid-path)
  (eprintf "[DAEMON] Starting service...~n")
  
  ;; Install signal handlers
  ;; (In production, use FFI for proper signal handling)
  
  ;; Run the service
  (with-handlers ([exn:break? (λ (e) 
                                (eprintf "~n[DAEMON] Shutting down...~n")
                                (remove-pid-file!)
                                (stop-service!))])
    (thunk)))

(define (run-daemon!)
  "Run the service as a daemon"
  (daemonize! 
   (λ ()
     (start-service!)
     ;; Keep running
     (let loop ()
       (sleep 1)
       (loop)))))

;; ============================================================================
;; Status and Control
;; ============================================================================

(define (service-status)
  "Get service status"
  (define pid (read-pid-file))
  (if pid
      (hash 'running #t 'pid pid)
      (hash 'running #f)))

(define (is-service-running?)
  "Check if service is running"
  (hash-ref (service-status) 'running #f))
