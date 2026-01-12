#lang racket/base
(provide responses-run-turn/stream)
(require racket/port racket/string json net/http-client racket/match net/url racket/list "../utils/utils-spinner.rkt")

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

(define (responses-run-turn/stream #:api-key api-key #:make-request mk-req #:tool-run tool-run #:emit! emit! #:cancelled? [cancelled? (λ () #f)] #:api-base [base "https://api.openai.com/v1"])
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

  (let loop ()
    (when (cancelled?) 
      (http-conn-close! hc)
      (when (and in (input-port? in))
        (close-input-port in))
      (error "Request cancelled"))
    (unless (and in (input-port? in))
      (http-conn-close! hc)
      (error "Input port is invalid or closed"))
    (with-handlers ([exn:fail? (λ (e)
                                  (http-conn-close! hc)
                                  (when (and in (input-port? in))
                                    (close-input-port in))
                                  (error (format "Error reading stream: ~a" (exn-message e))))])
      (define line (read-line in 'any))
      (cond
        [(eof-object? line) 
         (http-conn-close! hc)
         (when (and in (input-port? in))
           (close-input-port in))
         'done]
        [(string-prefix? line "data: [DONE]") (loop)]
        [(string-prefix? line "data: ")
         (define j (string->jsexpr (substring line 6)))
         
         ;; Check for usage stats in this chunk
         (when (hash-has-key? j 'usage)
           (set! final-usage (hash-ref j 'usage)))

         (unless (empty? (hash-ref j 'choices)) 
           (define delta (hash-ref (first (hash-ref j 'choices)) 'delta (hash)))
           (when (hash-has-key? delta 'content) 
             (define c (hash-ref delta 'content))
             (set! full-content (cons c full-content))
             (emit! c))
           (when (hash-has-key? delta 'tool_calls)
             (for ([tc (hash-ref delta 'tool_calls)])
               (define idx (hash-ref tc 'index))
               (define cur (hash-ref pending idx (hash 'args "")))
               (when (hash-has-key? tc 'id) (set! cur (hash-set cur 'id (hash-ref tc 'id))))
               (when (hash-has-key? tc 'function) 
                 (define fn (hash-ref tc 'function)) 
                 (when (hash-has-key? fn 'name) (set! cur (hash-set cur 'name (hash-ref fn 'name)))) 
                 (set! cur (hash-set cur 'args (string-append (hash-ref cur 'args) (hash-ref fn 'arguments "")))))
               (hash-set! pending idx cur))))
         (loop)]
        [else (loop)])))
  
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
      (define res (tool-run name args))
      (hash 'tool_call_id id 'role "tool" 'name name 'content (if (string? res) res (jsexpr->string res)))))
  
  ;; Close connection and port if still open
  (with-handlers ([exn:fail? (λ (_) (void))])
    (http-conn-close! hc)
    (when (and in (input-port? in))
      (close-input-port in)))
  
  (values assistant-msg tool-results final-usage))