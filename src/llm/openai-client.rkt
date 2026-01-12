#lang racket
(provide make-openai-sender validate-api-key make-openai-image-generator summarize-conversation estimate-tokens)
(require net/http-client json net/url racket/string "../utils/utils-spinner.rkt")

(define (make-openai-sender #:model [model "gpt-5.2"] #:api-key [key #f] #:api-base [base "https://api.openai.com/v1"])
  (define k (or key (getenv "OPENAI_API_KEY")))
  (define provider (detect-provider-from-base base))
  (define u (string->url base))
  (define host (url-host u))
  (define port (or (url-port u) (if (equal? (url-scheme u) "https") 443 80)))
  (define ssl? (equal? (url-scheme u) "https"))
  
  ;; Reconstruct path prefix from URL struct (e.g. /v1)
  (define base-path 
    (string-join 
     (map (λ (p) (path/param-path p)) (url-path u)) 
     "/"))
  
  ;; For Backboard, use /api/chat/completions, otherwise use /v1/chat/completions or base-path/chat/completions
  (define endpoint
    (if (eq? provider 'backboard)
        (let ([has-api? (string-contains? base "/api")])
          (if has-api?
              "/api/chat/completions"
              (string-append base-path "/api/chat/completions")))
        (string-append "/" base-path "/chat/completions")))
  
  ;; Fix double slashes if base path is empty or malformed
  (define safe-endpoint (string-replace endpoint "//" "/"))
  
  ;; Use appropriate header format based on provider
  (define auth-header
    (cond
      [(eq? provider 'backboard)
       (format "X-API-Key: ~a" k)]
      [else
       (format "Authorization: Bearer ~a" k)]))

  (λ (prompt)
    (define headers (list auth-header "Content-Type: application/json"))
    (define content 
      (cond 
        [(string? prompt) prompt]
        [(list? prompt) prompt] ; Already structured
        [else (format "~a" prompt)]))
    
    (define payload (jsexpr->bytes (hash 'model model 'response_format (hash 'type "json_object") 'messages (list (hash 'role "user" 'content content)))))
    (define start-time (current-inexact-milliseconds))
    (define s-thread (start-spinner! "Thinking...")) ;; User feedback
    (define-values (status _ in) (http-sendrecv host safe-endpoint #:port port #:method "POST" #:headers headers #:data payload #:ssl? ssl?))
    (stop-spinner! s-thread)
    (define end-time (current-inexact-milliseconds))
    
    (define res-bytes (port->bytes in))
    (close-input-port in)
    (define res (bytes->jsexpr res-bytes))
    
    (if (string-prefix? (bytes->string/utf-8 status) "HTTP/1.1 200")
        (let ([meta (hash-copy (hash-ref res 'usage (hash)))])
          (hash-set! meta 'elapsed_ms (- end-time start-time))
          (hash-set! meta 'model model)
          (values #t 
                  (hash-ref (hash-ref (first (hash-ref res 'choices)) 'message) 'content) 
                  meta))
        (values #f (format "Error: ~a" res) (hash)))))

(define (detect-provider-from-base base-url)
  (cond
    [(string-contains? base-url "api.openai.com") 'openai]
    [(string-contains? base-url "openrouter.ai") 'openrouter]
    [(string-contains? base-url "api.anthropic.com") 'anthropic]
    [(string-contains? base-url "api.together.xyz") 'together]
    [(string-contains? base-url "api.groq.com") 'groq]
    [(string-contains? base-url "backboard.io") 'backboard]
    [else 'custom]))

(define (validate-api-key [key #f] [base "https://api.openai.com/v1"])
  (define k (or key (getenv "OPENAI_API_KEY")))
  (unless k (error "No API key provided"))
  
  (define provider (detect-provider-from-base base))
  (define clean-base (if (string-suffix? base "/")
                         (substring base 0 (sub1 (string-length base)))
                         base))
  
  ;; Build endpoint URL based on provider
  (define endpoint-url
    (if (eq? provider 'backboard)
        (let ([has-api? (string-contains? clean-base "/api")])
          (if has-api?
              (string-append clean-base "/models")
              (string-append clean-base "/api/models")))
        (string-append clean-base "/models")))
  
  (define u (string->url endpoint-url))
  (define host (url-host u))
  (define port (or (url-port u) (if (equal? (url-scheme u) "https") 443 80)))
  (define ssl? (equal? (url-scheme u) "https"))
  
  (define base-path 
    (string-join 
     (map (λ (p) (path/param-path p)) (url-path u)) 
     "/"))
  (define safe-endpoint (string-append "/" base-path))
  
  ;; Use appropriate header format based on provider
  (define auth-header
    (cond
      [(eq? provider 'backboard)
       (format "X-API-Key: ~a" k)]
      [else
       (format "Authorization: Bearer ~a" k)]))
  
  (with-handlers ([exn:fail? (λ (e) (values #f (exn-message e)))])
    (define headers (list auth-header))
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
             
    (define s-thread (start-spinner! "Generating Image..."))
    (define-values (status _ in) (http-sendrecv host safe-endpoint #:port port #:method "POST" #:headers headers #:data payload #:ssl? ssl?))
    (stop-spinner! s-thread)
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