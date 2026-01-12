#lang racket/base
;; Chrysalis Forge HTTP/WebSocket Service Server
;; Main server entry point with CORS, request handling, and WebSocket support

(provide (all-defined-out))

(require racket/string racket/match racket/port json racket/file racket/path
         net/url)

(require "config.rkt" "db.rkt" "api-router.rkt")

;; ============================================================================
;; Simple HTTP Server using net/tcp
;; ============================================================================

(require racket/tcp)

(define (parse-http-request in)
  "Parse an HTTP request from input port"
  (define first-line (read-line in 'any))
  (when (eof-object? first-line)
    (error 'parse-http-request "Empty request"))
  
  (define parts (string-split first-line " "))
  (define method (car parts))
  (define path-with-query (cadr parts))
  
  ;; Parse path and query string
  (define path-parts (string-split path-with-query "?"))
  (define path (car path-parts))
  (define query-string (if (> (length path-parts) 1) (string-join (cdr path-parts) "?") ""))
  
  ;; Parse query params
  (define query
    (if (equal? query-string "")
        (hash)
        (for/hash ([pair (string-split query-string "&")])
          (define kv (string-split pair "="))
          (values (string->symbol (car kv)) 
                  (if (> (length kv) 1) (cadr kv) "")))))
  
  ;; Parse headers
  (define headers
    (let loop ([headers (hash)])
      (define line (read-line in 'any))
      (cond
        [(or (eof-object? line) (equal? line "") (equal? line "\r"))
         headers]
        [else
         (define colon-pos (string-contains? line ":"))
         (if colon-pos
             (loop (hash-set headers 
                            (string->symbol (string-downcase (string-trim (substring line 0 colon-pos))))
                            (string-trim (substring line (add1 colon-pos)))))
             (loop headers))])))
  
  ;; Read body if Content-Length header exists
  (define content-length 
    (let ([cl (hash-ref headers 'content-length #f)])
      (and cl (string->number cl))))
  
  (define body
    (if (and content-length (> content-length 0))
        (read-string content-length in)
        ""))
  
  (hash 'method method
        'path path
        'query query
        'headers headers
        'body body))

(define (format-http-response status headers body)
  "Format an HTTP response"
  (define status-line 
    (format "HTTP/1.1 ~a ~a\r\n" status (status-code->message status)))
  (define header-lines
    (string-join 
     (for/list ([(k v) (in-hash headers)])
       (format "~a: ~a" k v))
     "\r\n"))
  (string-append status-line header-lines "\r\nContent-Length: " 
                 (number->string (string-length body)) "\r\n\r\n" body))

(define (status-code->message code)
  (match code
    [200 "OK"]
    [201 "Created"]
    [204 "No Content"]
    [400 "Bad Request"]
    [401 "Unauthorized"]
    [403 "Forbidden"]
    [404 "Not Found"]
    [405 "Method Not Allowed"]
    [429 "Too Many Requests"]
    [500 "Internal Server Error"]
    [_ "Unknown"]))

;; ============================================================================
;; CORS Handling
;; ============================================================================

(define (add-cors-headers response allowed-origins)
  "Add CORS headers to response"
  (define existing-headers (hash-ref response 'headers '()))
  (define cors-headers
    (list (cons 'Access-Control-Allow-Origin 
                (if (equal? allowed-origins '("*")) "*" 
                    (string-join allowed-origins ", ")))
          (cons 'Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS")
          (cons 'Access-Control-Allow-Headers "Content-Type, Authorization, X-API-Key")
          (cons 'Access-Control-Max-Age "86400")))
  (hash-set response 'headers (append existing-headers cors-headers)))

(define (handle-options-request request config)
  "Handle CORS preflight requests"
  (define allowed-origins (SecurityConfig-allowed-origins 
                           (ServiceConfig-security config)))
  (add-cors-headers (hash 'status 204 'headers '() 'body "") allowed-origins))

;; ============================================================================
;; Request Handler
;; ============================================================================

(define (handle-request request config)
  "Handle a single HTTP request"
  (define method (hash-ref request 'method))
  (define allowed-origins (SecurityConfig-allowed-origins 
                           (ServiceConfig-security config)))
  
  ;; Handle CORS preflight
  (if (equal? method "OPTIONS")
      (handle-options-request request config)
      ;; Route the request
      (let ([response (route-request request)])
        (add-cors-headers response allowed-origins))))

(define (handle-connection in out config)
  "Handle a TCP connection"
  (with-handlers ([exn:fail? (λ (e) 
                               (eprintf "[HTTP] Error: ~a~n" (exn-message e))
                               (display (format-http-response 
                                        500 
                                        (hash 'Content-Type "application/json")
                                        (jsexpr->string (hash 'error (exn-message e))))
                                       out))])
    (define request (parse-http-request in))
    (define response (handle-request request config))
    
    (define status (hash-ref response 'status 200))
    (define headers-list (hash-ref response 'headers '()))
    (define body (hash-ref response 'body ""))
    
    ;; Convert headers list to hash
    (define headers-hash
      (for/hash ([h headers-list])
        (values (car h) (cdr h))))
    
    ;; Ensure Content-Type is set
    (define final-headers 
      (if (hash-has-key? headers-hash 'Content-Type)
          headers-hash
          (hash-set headers-hash 'Content-Type "application/json")))
    
    (display (format-http-response status final-headers body) out)
    (flush-output out)))

;; ============================================================================
;; Server Lifecycle
;; ============================================================================

(define current-server-listener (make-parameter #f))
(define current-server-shutdown (make-parameter #f))
(define server-running? (make-parameter #f))

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
  
  ;; Start TCP listener
  (define listener (tcp-listen server-port 128 #t server-host))
  (current-server-listener listener)
  (server-running? #t)
  
  ;; Accept connections in a loop
  (let loop ()
    (when (server-running?)
      (with-handlers ([exn:fail? (λ (e) 
                                   (unless (not (server-running?))
                                     (eprintf "[HTTP] Accept error: ~a~n" (exn-message e))))])
        (define-values (in out) (tcp-accept listener))
        ;; Handle in a thread
        (thread 
         (λ ()
           (with-handlers ([exn:fail? (λ (e) (eprintf "[HTTP] Handler error: ~a~n" (exn-message e)))])
             (handle-connection in out cfg)
             (close-input-port in)
             (close-output-port out)))))
      (loop)))
  
  listener)

(define (stop-service!)
  "Stop the HTTP service"
  (server-running? #f)
  (when (current-server-listener)
    (tcp-close (current-server-listener))
    (current-server-listener #f))
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

;; Export for current-process-id
(require ffi/unsafe)
(define current-process-id
  (get-ffi-obj "getpid" #f (_fun -> _int)))
