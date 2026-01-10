#lang racket/base
(require rackunit
         "../utils-retry.rkt")

(provide utils-retry-tests)

(define utils-retry-tests
  (test-suite
   "utils-retry tests"
   
   (test-case
    "with-retry success"
    (check-equal? (with-retry (λ () "success")) "success"))
   
   (test-case
    "with-retry eventually succeeds"
    (let ([calls 0])
      (define result
        (with-retry 
         (λ () 
           (set! calls (add1 calls))
           (if (< calls 2)
               (error "fail")
               "success"))
         #:retries 3
         #:delay-ms 1))
      (check-equal? result "success")
      (check-equal? calls 2)))
   
   (test-case
    "with-retry fails after retries"
    (check-exn
     exn:fail?
     (λ ()
       (with-retry 
        (λ () (error "always fail"))
        #:retries 2
        #:delay-ms 1))))))

(module+ test
  (require rackunit/text-ui)
  (run-tests utils-retry-tests))
