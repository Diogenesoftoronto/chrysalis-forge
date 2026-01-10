#lang racket/base
(provide responses-run-turn/stream)
(require racket/port racket/string json net/http-client racket/match net/url racket/list "../utils/utils-spinner.rkt")

(define (http-post/stream api-key payload host port endpoint ssl?)
  (define hc (http-conn-open host #:port port #:ssl? ssl?))
  (define body (jsexpr->bytes payload))
  (define headers (list "Content-Type: application/json" (format "Authorization: Bearer ~a" api-key)))
  (http-conn-send! hc endpoint #:method "POST" #:headers headers #:data body)
  (define-values (status _ in) (http-conn-recv! hc #:method "POST" #:close? #f))
  (values status in hc))

(define (responses-run-turn/stream #:api-key api-key #:make-request mk-req #:tool-run tool-run #:emit! emit! #:cancelled? [cancelled? (λ () #f)] #:api-base [base "https://api.openai.com/v1"])
  ;; Parse API Base
  (define u (string->url base))
  (define host (url-host u))
  (define port (or (url-port u) (if (equal? (url-scheme u) "https") 443 80)))
  ;; Construct strict endpoint path
  (define endpoint (string-append "/" (string-join (map path/param-path (url-path u)) "/") "/chat/completions"))
  
  ;; Inject stream_options for usage
  (define req (mk-req))
  (define req-with-usage (hash-set req 'stream_options (hash 'include_usage #t)))

  (define hc (http-conn-open host #:port port #:ssl? 'auto))
  (define body (jsexpr->bytes req-with-usage))
  (define headers (list "Content-Type: application/json" (format "Authorization: Bearer ~a" api-key)))
  
  (define s-thread (start-spinner! "Thinking...")) ;; User feedback
  (http-conn-send! hc endpoint #:method "POST" #:headers headers #:data body)
  (define-values (status _ in) (http-conn-recv! hc #:method "POST" #:close? #f))
  (stop-spinner! s-thread)
  (define pending (make-hash)) 
  (define final-usage (hash))
  (define full-content '())

  (let loop ()
    (when (cancelled?) (http-conn-close! hc))
    (define line (read-line in 'any))
    (cond
      [(eof-object? line) (http-conn-close! hc) 'done]
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
      [else (loop)]))
  
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
  
  (values assistant-msg tool-results final-usage))