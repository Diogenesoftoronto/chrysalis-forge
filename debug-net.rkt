#lang racket/base
(require net/http-client net/url json racket/list racket/port)

(define api-key "7a99e660aedd4f048bceaada7e0dd47d.iRfUET2HPnjhBIro")
(define endpoint-str "https://api.z.ai/api/coding/paas/v4/chat/completions")
(define u (string->url endpoint-str))

(printf "Connecting to ~a port ~a...\n" (url-host u) (or (url-port u) 443))

(define-values (status headers in)
  (http-sendrecv (url-host u)
                 "/api/coding/paas/v4/chat/completions" 
                 #:ssl? 'auto
                 #:port (or (url-port u) 443)
                 #:method "POST"
                 #:headers (list "Content-Type: application/json"
                                 (format "Authorization: Bearer ~a" api-key))
                 #:data (jsexpr->bytes (hash 'model "glm-4.7" 'messages (list (hash 'role "user" 'content "hi")) 'stream #f))))

(printf "Status: ~a\n" status)
(printf "Headers: ~a\n" headers)
(displayln (port->string in))
