#lang racket/base
(provide run-tiered-code! SECURITY-LEVELS)
(require racket/sandbox racket/file racket/port)

(define SECURITY-LEVELS (hash 'SANDBOX 0 'NET-READ 1 'FULL-FS 2 'GOD-MODE 3))
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

(define (run-tiered-code! code level)
  (with-handlers ([exn:fail? (λ (e) (format "[RACKET ERROR]: ~a" (exn-message e)))])
    (define ev (make-tiered-evaluator level))
    (format "RESULT:\n~a" (ev (read (open-input-string code))))))