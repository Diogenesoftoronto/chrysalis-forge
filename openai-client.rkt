#lang racket
(provide make-openai-sender validate-api-key make-openai-image-generator)
(require net/http-client json net/url racket/string)

(define (make-openai-sender #:model [model "gpt-5.2"] #:api-key [key #f] #:api-base [base "https://api.openai.com/v1"])
  (define k (or key (getenv "OPENAI_API_KEY")))
  (define u (string->url base))
  (define host (url-host u))
  (define port (or (url-port u) (if (equal? (url-scheme u) "https") 443 80)))
  (define ssl? (equal? (url-scheme u) "https"))
  
  ;; Reconstruct path prefix from URL struct (e.g. /v1)
  (define base-path 
    (string-join 
     (map (λ (p) (path/param-path p)) (url-path u)) 
     "/"))
  
  (define endpoint (string-append "/" base-path "/chat/completions"))
  ;; Fix double slashes if base path is empty or malformed
  (define safe-endpoint (string-replace endpoint "//" "/"))

  (λ (prompt)
    (define headers (list (format "Authorization: Bearer ~a" k) "Content-Type: application/json"))
    (define content 
      (cond 
        [(string? prompt) prompt]
        [(list? prompt) prompt] ; Already structured
        [else (format "~a" prompt)]))
    
    (define payload (jsexpr->bytes (hash 'model model 'response_format (hash 'type "json_object") 'messages (list (hash 'role "user" 'content content)))))
    (define-values (status _ in) (http-sendrecv host safe-endpoint #:port port #:method "POST" #:headers headers #:data payload #:ssl? ssl?))
    (define res (bytes->jsexpr (port->bytes in)))
    (close-input-port in)
    (if (string-prefix? (bytes->string/utf-8 status) "HTTP/1.1 200")
        (values #t 
                (hash-ref (hash-ref (first (hash-ref res 'choices)) 'message) 'content) 
                (hash-ref res 'usage (hash))) ; Return usage metrics
        (values #f (format "Error: ~a" res) (hash)))))

(define (validate-api-key [key #f] [base "https://api.openai.com/v1"])
  (define k (or key (getenv "OPENAI_API_KEY")))
  (unless k (error "No API key provided"))
  (define u (string->url (string-append base "/models")))
  (define host (url-host u))
  (define port (or (url-port u) (if (equal? (url-scheme u) "https") 443 80)))
  (define ssl? (equal? (url-scheme u) "https"))
  
  (define base-path 
    (string-join 
     (map (λ (p) (path/param-path p)) (url-path u)) 
     "/"))
  (define safe-endpoint (string-append "/" base-path))
  
  (with-handlers ([exn:fail? (λ (e) (values #f (exn-message e)))])
    (define headers (list (format "Authorization: Bearer ~a" k)))
    (define-values (status _ in) (http-sendrecv host safe-endpoint #:port port #:method "GET" #:headers headers #:ssl? ssl?))
    (define res-status (bytes->string/utf-8 status))
    (close-input-port in)
    (if (string-prefix? res-status "HTTP/1.1 200")
        (values #t "OK")
        (values #f res-status))))

(define (make-openai-image-generator #:model [model "gpt-image"] #:api-key [key #f] #:api-base [base "https://api.openai.com/v1"])
  (define k (or key (getenv "OPENAI_API_KEY")))
  (define u (string->url base))
  (define host (url-host u))
  (define port (or (url-port u) (if (equal? (url-scheme u) "https") 443 80)))
  (define ssl? (equal? (url-scheme u) "https"))

  (define base-path 
    (string-join 
     (map (λ (p) (path/param-path p)) (url-path u)) 
     "/"))
  
  (define endpoint (string-append "/" base-path "/images/generations"))
  (define safe-endpoint (string-replace endpoint "//" "/"))

  (λ (prompt)
    (define headers (list (format "Authorization: Bearer ~a" k) "Content-Type: application/json"))
    (define payload 
      (jsexpr->bytes 
       (hash 'model model 
             'prompt prompt 
             'n 1 
             'size "1024x1024")))
             
    (define-values (status _ in) (http-sendrecv host safe-endpoint #:port port #:method "POST" #:headers headers #:data payload #:ssl? ssl?))
    (define res (bytes->jsexpr (port->bytes in)))
    (close-input-port in)
    
    (if (string-prefix? (bytes->string/utf-8 status) "HTTP/1.1 200")
        (values #t (hash-ref (first (hash-ref res 'data)) 'url))
        (values #f (format "Image Gen Error: ~a" res)))))