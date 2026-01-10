#lang racket/base
(provide run-tiered-code! run-code-with-retry! SECURITY-LEVELS)
(require racket/sandbox racket/file racket/port "../utils/debug.rkt")

(define SECURITY-LEVELS (hash 'SANDBOX 0 'NET-READ 1 'FULL-FS 2 'CONFIRMED-GOD 3 'AUTO-GOD 4))
(define WORKSPACE (build-path (find-system-path 'home-dir) ".agentd" "workspace"))
(make-directory* WORKSPACE)

(define (make-tiered-evaluator level)
  (sandbox-eval-limits '(60 512))
  (define (allow-net? _ _2 _3) (>= level 1))
  (define paths
    (cond [(= level 0) (list (list 'write WORKSPACE) (list 'read WORKSPACE) (list 'read (find-system-path 'lib-dir)))]
          [(= level 1) (list (list 'write WORKSPACE) (list 'read "/") (list 'read (find-system-path 'lib-dir)))]
          [(>= level 2) (list (list 'write "/"))]))
  (parameterize ([sandbox-path-permissions paths] [sandbox-network-guard allow-net?])
    (define ev (make-evaluator 'racket/base))
    (when (>= level 1) (ev '(require net/url net/http-client racket/file racket/system json)))
    ev))

;; Basic execution (no retry)
(define (run-tiered-code! code level)
  (log-debug 1 'sandbox "Exec (Level ~a): ~a" level (substring code 0 (min 50 (string-length code))))
  (with-handlers ([exn:fail? (λ (e) (format "[RACKET ERROR]: ~a" (exn-message e)))])
    (define ev (make-tiered-evaluator level))
    (define res (ev (read (open-input-string code))))
    (log-debug 2 'sandbox "Result: ~a" res)
    (format "RESULT:\n~a" res)))

;; Auto-correction loop: retries on error, returns structured result
;; Returns (values success? result-or-error attempts)
(define (run-code-with-retry! code level #:max-retries [max-retries 3] #:fix-fn [fix-fn #f])
  (let loop ([current-code code] [attempt 1])
    (log-debug 1 'sandbox "Attempt ~a/~a (Level ~a)" attempt max-retries level)
    (define result
      (with-handlers ([exn:fail? (λ (e) (cons 'error (exn-message e)))])
        (define ev (make-tiered-evaluator level))
        (define res (ev (read (open-input-string current-code))))
        (cons 'ok res)))
    (cond
      [(eq? (car result) 'ok)
       (values #t (format "RESULT:\n~a" (cdr result)) attempt)]
      [(>= attempt max-retries)
       (values #f (format "[FAILED after ~a attempts]: ~a\nLast code:\n~a" attempt (cdr result) current-code) attempt)]
      [fix-fn
       ;; If a fix function is provided, use it to get corrected code
       (define fixed-code (fix-fn current-code (cdr result)))
       (if fixed-code
           (loop fixed-code (add1 attempt))
           (values #f (format "[FAILED]: ~a\nNo fix available." (cdr result)) attempt))]
      [else
       ;; No fix function, just return the error
       (values #f (format "[ERROR]: ~a\nCode:\n~a" (cdr result) current-code) attempt)])))