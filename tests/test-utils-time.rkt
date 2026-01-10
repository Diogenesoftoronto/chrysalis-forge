#lang racket/base
(require rackunit
         "../src/utils/utils-time.rkt")

(provide utils-time-tests)

(define utils-time-tests
  (test-suite
   "utils-time tests"
   
   (test-case
    "parse-duration basics"
    (check-equal? (parse-duration #f) +inf.0 "False should be infinite")
    (check-equal? (parse-duration "30") 30 "Number string should be seconds")
    (check-equal? (parse-duration "10s") 10 "s suffix should be seconds")
    (check-equal? (parse-duration "5m") 300 "m suffix should be minutes")
    (check-equal? (parse-duration "1h") 3600 "h suffix should be hours")
    (check-equal? (parse-duration "invalid") +inf.0 "Invalid format should be infinite"))))

(module+ test
  (require rackunit/text-ui)
  (run-tests utils-time-tests))
