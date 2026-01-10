#lang racket/base
(provide parse-duration)
(require racket/string racket/list)

(define (parse-duration s)
  (cond
    [(not s) +inf.0]
    [(string->number s) (string->number s)] ; plain number = seconds
    [else
     (let ([len (string-length s)])
       (if (< len 2) 
           (or (string->number s) +inf.0)
           (let* ([unit (substring s (- len 1) len)]
                  [val (string->number (substring s 0 (- len 1)))])
             (if (not val)
                 +inf.0
                 (case unit
                   [("s") val]
                   [("m") (* val 60)]
                   [("h") (* val 3600)]
                   [else +inf.0])))))]))
