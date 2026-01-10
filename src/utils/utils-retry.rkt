#lang racket/base
(provide with-retry)
(require)

(define (with-retry fn #:retries [retries 3] #:delay-ms [delay-ms 1000])
  (let loop ([r retries])
    (with-handlers ([exn:fail? 
                     (λ (e)
                       (if (> r 0)
                           (begin
                             (eprintf "[WARN] Network fail: ~a. Retrying in ~ams...\n" (exn-message e) delay-ms)
                             (sleep (/ delay-ms 1000.0))
                             (loop (sub1 r)))
                           (raise e)))])
      (fn))))