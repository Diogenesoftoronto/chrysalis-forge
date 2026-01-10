#lang racket/base
(require rackunit
         "../acp-tools.rkt")

(provide acp-tools-tests)

(define acp-tools-tests
  (test-suite
   "acp-tools tests"
   
   (test-case
    "make-acp-tools structure"
    (define tools (make-acp-tools))
    (check-pred list? tools)
    (check-equal? (length tools) 2)
    
    (define read-tool (car tools))
    (check-equal? (hash-ref (hash-ref read-tool 'function) 'name) "read_file")
    
    (define write-tool (cadr tools))
    (check-equal? (hash-ref (hash-ref write-tool 'function) 'name) "write_file"))))

(module+ test
  (require rackunit/text-ui)
  (run-tests acp-tools-tests))
