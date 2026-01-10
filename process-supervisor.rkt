#lang racket
(provide spawn-service! stop-service! list-services! get-supervisor-tools)
(require racket/async-channel json "openai-responses-stream.rkt")

(struct Service (id cmd process output-port) #:mutable #:transparent)
(define SERVICES (make-hash))

(define (spawn-service! id cmd api-key)
  (define-values (sp out in err) (subprocess #f #f #f (find-executable-path (first (string-split cmd))) (rest (string-split cmd))))
  (hash-set! SERVICES id (Service id cmd sp out))
  (format "Service ~a started." id))

(define (stop-service! id)
  (define s (hash-ref SERVICES id #f))
  (when s (subprocess-kill (Service-process s) #t) (hash-remove! SERVICES id) "Stopped."))

(define (list-services!) (string-join (for/list ([k (hash-keys SERVICES)]) (format "~a" k)) "\n"))

(define (get-supervisor-tools)
  (list (hash 'type "function" 'function (hash 'name "service_start" 'parameters (hash 'type "object" 'properties (hash 'id (hash 'type "string") 'cmd (hash 'type "string")))))
        (hash 'type "function" 'function (hash 'name "service_stop" 'parameters (hash 'type "object" 'properties (hash 'id (hash 'type "string")))))
        (hash 'type "function" 'function (hash 'name "service_list" 'parameters (hash 'type "object" 'properties (hash))))))