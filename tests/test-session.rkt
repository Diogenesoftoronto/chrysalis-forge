#lang racket
(require rackunit "../src/stores/context-store.rkt" racket/file json)

;; Setup test environment by temporarily overriding the DB path
;; We'll use environment variable approach instead of parameterize
(define test-home (build-path (current-directory) "test-env"))

(define (run-session-tests)
  (make-directory* test-home)
  (make-directory* (build-path test-home ".agentd"))
  
  ;; Use unique session name to avoid conflicts with previous runs
  (define test-session-name (format "test-session-~a" (current-seconds)))
  (define test-session-sym (string->symbol test-session-name))
  
  (test-case "Session Management - Basic Operations"
    ;; Test session creation
    (session-create! test-session-name)
    (define-values (sessions1 active1) (session-list))
    (check-not-false (member test-session-sym sessions1) "Created session should be in list")
    
    ;; Test session switch
    (session-switch! test-session-name)
    (define-values (sessions2 active2) (session-list))
    (check-equal? active2 test-session-sym "Active session should be the test session")
    
    ;; Test cannot delete active session
    (check-exn exn:fail? (λ () (session-delete! test-session-name)) 
               "Should not be able to delete active session")
    
    ;; Switch back and delete
    (session-switch! "default")
    (session-delete! test-session-name)
    (define-values (sessions3 active3) (session-list))
    (check-equal? (member test-session-sym sessions3) #f "Deleted session should not be in list"))
  
  ;; Cleanup
  (delete-directory/files test-home #:must-exist? #f)
  (printf "Session tests passed.\n"))

(run-session-tests)
