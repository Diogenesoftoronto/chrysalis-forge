#lang racket/base
(provide responses-run-turn/stream)
(require racket/port racket/string json net/http-client racket/match net/url racket/list)

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
  
  (http-conn-send! hc endpoint #:method "POST" #:headers headers #:data body)
  (define-values (status _ in) (http-conn-recv! hc #:method "POST" #:close? #f))
  (define pending (make-hash)) 
  (define final-usage (hash))

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
         (when (hash-has-key? delta 'content) (emit! (hash-ref delta 'content)))
         (when (hash-has-key? delta 'tool_calls)
           (for ([tc (hash-ref delta 'tool_calls)])
             (define idx (hash-ref tc 'index))
             (define cur (hash-ref pending idx (hash 'args "")))
             (when (hash-has-key? tc 'id) (set! cur (hash-set cur 'id (hash-ref tc 'id))))
             (when (hash-has-key? tc 'function) (define fn (hash-ref tc 'function)) (when (hash-has-key? fn 'name) (set! cur (hash-set cur 'name (hash-ref fn 'name)))) (set! cur (hash-set cur 'args (string-append (hash-ref cur 'args) (hash-ref fn 'arguments "")))))
             (hash-set! pending idx cur))))
       (loop)]
      [else (loop)]))
  
  (define tool-results 
    (for/list ([(_ v) (in-hash pending)])
      (define id (hash-ref v 'id))
      (define name (hash-ref v 'name))
      (define args (with-handlers ([exn:fail? (λ (_) (hash))]) (string->jsexpr (hash-ref v 'args))))
      (define res (tool-run name args))
      (hash 'tool_call_id id 'role "tool" 'name name 'content (if (string? res) res (jsexpr->string res)))))
  
  (values tool-results final-usage))