#lang racket/base
(provide current-debug-level log-debug log-section)
(require racket/format)

;; Debug Level: 0 = Silent, 1 = Info, 2 = Verbose
(define current-debug-level (make-parameter 0))

(define (log-debug level category msg . args)
  (when (>= (current-debug-level) level)
    (define timestamp (current-seconds)) ;; Could use better formatting
    (printf "[~a] [~a] ~a\n" 
            (string-upcase (symbol->string category)) 
            level 
            (apply format msg args))))

(define (log-section title)
  (when (>= (current-debug-level) 1)
    (printf "\n=== ~a ===\n" title)))
