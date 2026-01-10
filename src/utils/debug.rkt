#lang racket/base
(provide current-debug-level log-debug log-debug/once log-section)
(require racket/format racket/set)

;; Debug Level: 0 = Silent, 1 = Info, 2 = Verbose
(define current-debug-level (make-parameter 0))

(define seen-messages (make-hash))

(define (log-debug level category msg . args)
  (when (>= (current-debug-level) level)
    (printf "[~a] [~a] ~a\n" 
            (string-upcase (symbol->string category)) 
            level 
            (apply format msg args))))

(define (log-debug/once level category msg . args)
  (define content (apply format msg args))
  (when (>= (current-debug-level) level)
    (unless (hash-ref seen-messages content #f)
      (hash-set! seen-messages content #t)
      (printf "[~a] [~a] [ONCE] ~a\n" 
              (string-upcase (symbol->string category)) 
              level 
              content))))

(define (log-section title)
  (when (>= (current-debug-level) 1)
    (printf "\n=== ~a ===\n" title)))
