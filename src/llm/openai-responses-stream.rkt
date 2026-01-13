#lang racket/base
(provide responses-run-turn/stream)
(require racket/port racket/string json net/http-client racket/match net/url racket/list racket/async-channel "../utils/utils-spinner.rkt")

(define (detect-provider-from-base base-url)
  (cond
    [(string-contains? base-url "api.openai.com") 'openai]
    [(string-contains? base-url "openrouter.ai") 'openrouter]
    [(string-contains? base-url "api.anthropic.com") 'anthropic]
    [(string-contains? base-url "api.together.xyz") 'together]
    [(string-contains? base-url "api.groq.com") 'groq]
    [(string-contains? base-url "backboard.io") 'backboard]
    [else 'custom]))

(define (http-post/stream api-key payload host port endpoint ssl? #:provider [provider 'openai])
  (define hc (http-conn-open host #:port port #:ssl? ssl?))
  (define body (jsexpr->bytes payload))
  (define auth-header
    (cond
      [(eq? provider 'backboard)
       (format "X-API-Key: ~a" api-key)]
      [else
       (format "Authorization: Bearer ~a" api-key)]))
  (define headers (list "Content-Type: application/json" auth-header))
  (http-conn-send! hc endpoint #:method "POST" #:headers headers #:data body)
  (define-values (status _ in) (http-conn-recv! hc #:method "POST" #:close? #f))
  (values status in hc))

(define (responses-run-turn/stream #:api-key api-key #:make-request mk-req #:tool-run tool-run #:emit! emit! #:tool-emit! [tool-emit! (λ (_) (void))] #:cancelled? [cancelled? (λ () #f)] #:api-base [base "https://api.openai.com/v1"])
  ;; Parse API Base
  (define provider (detect-provider-from-base base))
  (define u (string->url base))
  (define host (url-host u))
  (define port (or (url-port u) (if (equal? (url-scheme u) "https") 443 80)))
  
  ;; Construct endpoint path based on provider
  (define base-path (string-join (map path/param-path (url-path u)) "/"))
  (define endpoint
    (if (eq? provider 'backboard)
        (let ([has-api? (string-contains? base "/api")])
          (if has-api?
              "/api/chat/completions"
              (string-append "/" base-path "/api/chat/completions")))
        (string-append "/" base-path "/chat/completions")))
  
  ;; Inject stream_options for usage
  (define req (mk-req))
  (define req-with-usage (hash-set req 'stream_options (hash 'include_usage #t)))

  ;; Validate API key
  (unless api-key
    (error "API key is required but not provided. Set OPENAI_API_KEY environment variable or pass #:api-key"))
  
  (define hc (http-conn-open host #:port port #:ssl? 'auto))
  (define body (jsexpr->bytes req-with-usage))
  (define auth-header
    (cond
      [(eq? provider 'backboard)
       (format "X-API-Key: ~a" api-key)]
      [else
       (format "Authorization: Bearer ~a" api-key)]))
  (define headers (list "Content-Type: application/json" auth-header))
  
  (define s-thread (start-spinner! "Thinking...")) ;; User feedback
  (http-conn-send! hc endpoint #:method "POST" #:headers headers #:data body)
  (define-values (status _ in) (http-conn-recv! hc #:method "POST" #:close? #f))
  (stop-spinner! s-thread)
  
  ;; Check HTTP status code and validate input port
  (define status-str (bytes->string/utf-8 status))
  (unless (string-prefix? status-str "HTTP/1.1 200")
    ;; Read error response if port is valid, otherwise just use status
    (define req-model (hash-ref req 'model "unknown"))
    (define error-msg
      (cond
        [(and in (input-port? in))
         (with-handlers ([exn:fail? (λ (e) 
                                       (http-conn-close! hc)
                                       (format "HTTP error: ~a (error reading response: ~a)" status-str (exn-message e)))])
           (define error-body-bytes (port->bytes in))
           (close-input-port in)
           (http-conn-close! hc)
           (if (> (bytes-length error-body-bytes) 0)
               (with-handlers ([exn:fail? (λ (_) (bytes->string/utf-8 error-body-bytes))])
                 (define error-body-str (bytes->string/utf-8 error-body-bytes))
                 (define error-json (string->jsexpr error-body-str))
                 (if (and (hash? error-json) (hash-has-key? error-json 'error))
                     (let ([error-obj (hash-ref error-json 'error)])
                       (if (hash? error-obj)
                           (hash-ref error-obj 'message error-body-str)
                           error-body-str))
                     error-body-str))
               (format "HTTP error: ~a (empty response body)" status-str)))]
        [else
         (http-conn-close! hc)
         (format "HTTP error: ~a (no response body available)" status-str)]))
    ;; Provide helpful error message with model info
    (define helpful-msg
      (if (string-contains? (string-downcase error-msg) "model")
          (format "~a\n\n[HELP] The model '~a' may not be valid for your API endpoint (~a).\n       Try setting a different model with:\n       export MODEL=<model-name>\n       or use: /config model <model-name>\n       Use '/config list' to see current settings." 
                  error-msg req-model base)
          error-msg))
    (error (format "API request failed (~a): ~a" status-str helpful-msg)))
  
  ;; Validate input port before proceeding
  (unless (and in (input-port? in))
    (http-conn-close! hc)
    (error (format "Invalid response: received ~a instead of input port" in)))
  
  (define pending (make-hash)) 
  (define final-usage (hash))
  (define full-content '())

  ;; === Threaded streaming with async-channel for better performance ===
  ;; Reader thread pushes parsed SSE events; consumer loop coalesces and rate-limits emit!
  
  (define sse-chan (make-async-channel))
  
  ;; Tagged message constructor for reader -> consumer communication
  (define (make-msg type . kvs)
    (apply hash 'type type kvs))
  
  ;; Reader thread: handles blocking I/O, sends structured events
  (define reader-thread
    (thread
     (λ ()
       (with-handlers ([exn:fail?
                        (λ (e)
                          (async-channel-put sse-chan (make-msg 'error 'message (exn-message e))))])
         (let loop ()
           (define line (read-line in 'any))
           (cond
             [(eof-object? line)
              (async-channel-put sse-chan (make-msg 'eof))
              (void)]
             [(string-prefix? line "data: [DONE]")
              (async-channel-put sse-chan (make-msg 'done))
              (loop)]
             [(string-prefix? line "data: ")
              (async-channel-put sse-chan (make-msg 'data 'json-line (substring line 6)))
              (loop)]
             [else (loop)]))))))
  
  ;; Tuning parameters for rate-limited, coalesced streaming
  (define flush-interval-ms 40.0)  ; ~25 FPS for smooth display
  (define max-batch-chars 256)     ; flush when buffer exceeds this
  
  (define (flush-buffer! buf)
    (unless (zero? (string-length buf))
      (emit! buf)))
  
  ;; Helper to cleanup resources
  (define (cleanup!)
    (with-handlers ([exn:fail? (λ (_) (void))])
      (http-conn-close! hc)
      (when (and in (input-port? in))
        (close-input-port in))
      (when (thread-running? reader-thread)
        (kill-thread reader-thread))))
  
  ;; Consumer loop: rate-limited emit with chunk coalescing
  (let consumer-loop ([buf ""] 
                      [last-flush-ms (current-inexact-milliseconds)]
                      [done? #f])
    ;; Check for cancellation
    (when (cancelled?)
      (cleanup!)
      (error "Request cancelled"))
    
    ;; Calculate timeout for sync
    (define now (current-inexact-milliseconds))
    (define time-since-flush (- now last-flush-ms))
    (define remaining-ms (max 0.0 (- flush-interval-ms time-since-flush)))
    (define timeout-secs (/ remaining-ms 1000.0))
    
    ;; Wait for event or timeout
    ;; When done? is true, we're waiting for EOF but still need to avoid busy-waiting
    (define msg
      (cond
        [done? 
         ;; Use a small timeout to avoid busy-waiting while waiting for EOF
         (sync/timeout 0.1 sse-chan)]
        [else (sync/timeout timeout-secs sse-chan)]))
    
    (cond
      ;; Timeout: flush accumulated buffer
      [(not msg)
       (when (> time-since-flush 0)
         (flush-buffer! buf))
       ;; If we're done? and timeout, check if reader thread is still alive
       ;; If thread is dead, we've missed EOF - treat as completion
       (if (and done? (not (thread-running? reader-thread)))
           (begin
             (flush-buffer! buf)
             (cleanup!)
             (void))
           (consumer-loop "" (current-inexact-milliseconds) done?))]
      
      ;; Error from reader thread
      [(eq? (hash-ref msg 'type) 'error)
       (flush-buffer! buf)
       (cleanup!)
       (error (format "Error reading stream: ~a" (hash-ref msg 'message)))]
      
      ;; EOF: flush, wait for reader thread to finish, then cleanup and exit
      [(eq? (hash-ref msg 'type) 'eof)
       (flush-buffer! buf)
       ;; Wait for reader thread to complete before cleaning up
       (with-handlers ([exn:fail? (λ (_) (void))])
         (when (thread-running? reader-thread)
           (thread-wait reader-thread)))
       (cleanup!)
       (void)]
      
      ;; [DONE] marker: keep draining until EOF
      [(eq? (hash-ref msg 'type) 'done)
       (consumer-loop buf last-flush-ms #t)]
      
      ;; Data chunk: parse JSON and update state
      [(eq? (hash-ref msg 'type) 'data)
       (define json-str (hash-ref msg 'json-line))
       (define j (with-handlers ([exn:fail? (λ (e)
                                               (flush-buffer! buf)
                                               (cleanup!)
                                               (error (format "JSON parse error: ~a in: ~a" 
                                                              (exn-message e) json-str)))])
                   (string->jsexpr json-str)))
       
       ;; Track usage stats
       (when (hash-has-key? j 'usage)
         (set! final-usage (hash-ref j 'usage)))
       
       ;; Process choices
       (define new-buf
         (if (and (hash-has-key? j 'choices) (not (empty? (hash-ref j 'choices))))
             (let* ([choice (first (hash-ref j 'choices))]
                    [delta (hash-ref choice 'delta (hash))])
               ;; Handle content delta
               (define content-buf
                 (if (hash-has-key? delta 'content)
                     (let ([c (hash-ref delta 'content)])
                       (set! full-content (cons c full-content))
                       (string-append buf c))
                     buf))
               ;; Handle tool calls delta
               (when (hash-has-key? delta 'tool_calls)
                 (for ([tc (hash-ref delta 'tool_calls)])
                   (define idx (hash-ref tc 'index))
                   (define cur (hash-ref pending idx (hash 'args "")))
                   (when (hash-has-key? tc 'id)
                     (set! cur (hash-set cur 'id (hash-ref tc 'id))))
                   (when (hash-has-key? tc 'function)
                     (define fn (hash-ref tc 'function))
                     (when (hash-has-key? fn 'name)
                       (set! cur (hash-set cur 'name (hash-ref fn 'name))))
                     (set! cur (hash-set cur 'args 
                                         (string-append (hash-ref cur 'args) 
                                                        (hash-ref fn 'arguments "")))))
                   (hash-set! pending idx cur)))
               content-buf)
             buf))
       
       ;; Decide whether to flush now
       (define new-now (current-inexact-milliseconds))
       (define new-time-since-flush (- new-now last-flush-ms))
       
       (if (or (>= (string-length new-buf) max-batch-chars)
               (>= new-time-since-flush flush-interval-ms))
           (begin
             (flush-buffer! new-buf)
             (consumer-loop "" (current-inexact-milliseconds) done?))
           (consumer-loop new-buf last-flush-ms done?))]
      
      ;; Unknown event: ignore
      [else (consumer-loop buf last-flush-ms done?)]))
  
  (define assistant-content (string-join (reverse full-content) ""))
  (define tool-calls 
    (for/list ([i (sort (hash-keys pending) <)])
      (define v (hash-ref pending i))
      (hash 'id (hash-ref v 'id) 'type "function" 'function (hash 'name (hash-ref v 'name) 'arguments (hash-ref v 'args)))))

  (define assistant-msg 
    (if (null? tool-calls)
        (hash 'role "assistant" 'content assistant-content)
        (hash 'role "assistant" 'content (if (string=? assistant-content "") (json-null) assistant-content) 'tool_calls tool-calls)))

  (define tool-results 
    (for/list ([i (sort (hash-keys pending) <)])
      (define v (hash-ref pending i))
      (define id (hash-ref v 'id))
      (define name (hash-ref v 'name))
      (define args (with-handlers ([exn:fail? (λ (_) (hash))]) (string->jsexpr (hash-ref v 'args))))
      ;; Emit tool_call start event for ACP
      (tool-emit! (hash 'event "start" 
                        'toolCallId id 
                        'title name 
                        'kind "other"
                        'rawInput args))
      ;; Emit in_progress status
      (tool-emit! (hash 'event "progress" 'toolCallId id))
      ;; Execute tool
      (define res 
        (with-handlers ([exn:fail? (λ (e) 
                                     (tool-emit! (hash 'event "finish" 
                                                       'toolCallId id 
                                                       'error #t 
                                                       'output (exn-message e)))
                                     (format "Error: ~a" (exn-message e)))])
          (define result (tool-run name args))
          (define output (if (string? result) result (jsexpr->string result)))
          ;; Emit tool_call finish event for ACP
          (tool-emit! (hash 'event "finish" 
                            'toolCallId id 
                            'error #f 
                            'output output))
          output))
      (hash 'tool_call_id id 'role "tool" 'name name 'content res)))
  
  ;; Close connection and port if still open
  (with-handlers ([exn:fail? (λ (_) (void))])
    (http-conn-close! hc)
    (when (and in (input-port? in))
      (close-input-port in)))
  
  (values assistant-msg tool-results final-usage))