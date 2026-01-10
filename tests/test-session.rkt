#lang racket
(require rackunit "../src/stores/context-store.rkt" racket/file json)

;; Setup test environment
(define test-home (build-path (current-directory) "test-env"))
(make-directory* test-home)
(parameterize ([find-system-path (λ (p) 
                                   (if (eq? p 'home-dir) 
                                       test-home 
                                       (find-system-path p)))])
  
  (delete-directory/files test-home #:must-exist? #f)
  
  (test-case "Session Management"
    ;; Initial state
    (check-equal? (begin (load-ctx) (ctx-get-active)) 
                  (ctx-get-active)) ; Should not error
    
    (define-values (sessions active) (session-list))
    (check-equal? active 'default)
    (check-equal? sessions '(default))
    
    ;; Create New
    (session-create! "test1")
    (define-values (s2 a2) (session-list))
    (check-equal? (length s2) 2)
    
    ;; Switch
    (session-switch! "test1")
    (define-values (s3 a3) (session-list))
    (check-equal? a3 'test1)
    
    ;; Delete
    (check-exn exn:fail? (λ () (session-delete! "test1"))) ; Cannot delete active
    
    (session-switch! "default")
    (session-delete! "test1")
    (define-values (s4 a4) (session-list))
    (check-equal? (length s4) 1)
    (check-equal? (first s4) 'default))
    
  (printf "Session tests passed.\n"))
