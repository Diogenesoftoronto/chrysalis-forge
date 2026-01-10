#lang racket
(provide make-openai-sender validate-api-key make-openai-image-generator summarize-conversation estimate-tokens)
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

;; Token Estimation (heuristic: ~0.75 words per token for English)
(define (estimate-tokens text)
  (inexact->exact (ceiling (* (length (string-split text)) 1.33))))

;; Estimate tokens for a list of messages
(define (estimate-messages-tokens msgs)
  (for/sum ([m msgs])
    (define content (hash-ref m 'content ""))
    (+ 4 ; overhead per message
       (if (string? content)
           (estimate-tokens content)
           (for/sum ([part (if (list? content) content '())])
             (if (equal? (hash-ref part 'type "") "text")
                 (estimate-tokens (hash-ref part 'text ""))
                 100)))))) ; image placeholder

;; Summarize a conversation for context compaction
(define (summarize-conversation messages #:model [model "gpt-5.2"] #:api-key [key #f] #:api-base [base "https://api.openai.com/v1"])
  (define sender (make-openai-sender #:model model #:api-key key #:api-base base))
  (define conversation-text
    (string-join
     (for/list ([m messages])
       (define role (hash-ref m 'role ""))
       (define content (hash-ref m 'content ""))
       (define text-content 
         (if (string? content) 
             content
             (string-join (filter string? (map (λ (p) (hash-ref p 'text #f)) (if (list? content) content '()))) "\n")))
       (format "[~a]: ~a" role text-content))
     "\n\n"))
  
  (define-values (ok? result _)
    (sender (format "Summarize this conversation into a concise summary that preserves all key facts, decisions, user preferences, and important context. The summary should be dense but complete enough to continue the conversation. Return JSON with a single 'summary' field.\n\n~a" conversation-text)))
  
  (if ok?
      (with-handlers ([exn:fail? (λ (_) (format "Summary: ~a" (substring result 0 (min 500 (string-length result)))))])
        (hash-ref (string->jsexpr result) 'summary result))
      ""))