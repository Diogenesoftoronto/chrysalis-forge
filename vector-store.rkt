#lang racket/base
(provide vector-add! vector-search)
(require json net/http-client racket/math "openai-client.rkt" net/url racket/string racket/port racket/list)

(define VEC-DB-PATH (build-path (find-system-path 'home-dir) ".agentd" "vectors.json"))
(define DB (make-hash)) ;; id -> (hash 'text "..." 'vec '(...))

;; Helper: Cosine Similarity
(define (cosine-sim v1 v2)
  (define dot (for/sum ([a v1] [b v2]) (* a b)))
  (define mag1 (sqrt (for/sum ([a v1]) (* a a))))
  (define mag2 (sqrt (for/sum ([b v2]) (* b b))))
  (if (or (zero? mag1) (zero? mag2)) 0.0 (/ dot (* mag1 mag2))))

;; Get Embedding from OpenAI
(define (get-embedding text key base)
  (define u (string->url base))
  (define host (url-host u))
  (define port (or (url-port u) (if (equal? (url-scheme u) "https") 443 80)))
  (define ssl? (equal? (url-scheme u) "https"))
  (define base-path (string-join (map (λ (p) (path/param-path p)) (url-path u)) "/"))
  (define endpoint (string-replace (string-append "/" base-path "/embeddings") "//" "/"))

  (define headers (list (format "Authorization: Bearer ~a" key) "Content-Type: application/json"))
  (define payload (jsexpr->bytes (hash 'input text 'model "text-embedding-3-small")))
  (define-values (status _ in) (http-sendrecv host endpoint #:port port #:method "POST" #:headers headers #:data payload #:ssl? ssl?))
  (define res (bytes->jsexpr (port->bytes in)))
  (hash-ref (first (hash-ref res 'data)) 'embedding))

(define (vector-add! text key [base "https://api.openai.com/v1"])
  (define vec (get-embedding text key base))
  (define id (number->string (current-milliseconds)))
  (hash-set! DB id (hash 'text text 'vec vec))
  "Stored.")

(define (vector-search query key [base "https://api.openai.com/v1"] [top-k 3])
  (define q-vec (get-embedding query key base))
  (define scored
    (for/list ([(id item) (in-hash DB)])
      (cons (cosine-sim q-vec (hash-ref item 'vec)) (hash-ref item 'text))))
  (take (sort scored > #:key car) (min top-k (hash-count DB))))