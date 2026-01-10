#lang racket/base
(provide load-dotenv!)
(require racket/file racket/string racket/system racket/list)

(define (load-dotenv!)
  (define path ".env")
  (when (file-exists? path)
    (for ([line (file->lines path)])
      (define trimmed (string-trim line))
      (unless (or (string=? trimmed "") (string-prefix? trimmed "#"))
        (define parts (string-split trimmed "=" #:trim? #f))
        (when (>= (length parts) 2)
          (putenv (first parts) (string-trim (string-join (rest parts) "=") "\"")))))))