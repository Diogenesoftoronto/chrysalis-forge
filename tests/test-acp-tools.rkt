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
    (check-equal? (length tools) 11)
    
    ;; Check read_file and write_file
    (define read-tool (car tools))
    (check-equal? (hash-ref (hash-ref read-tool 'function) 'name) "read_file")
    
    (define write-tool (cadr tools))
    (check-equal? (hash-ref (hash-ref write-tool 'function) 'name) "write_file")
    
    ;; Check new tools exist
    (define tool-names (map (λ (t) (hash-ref (hash-ref t 'function) 'name)) tools))
    (check-not-false (member "patch_file" tool-names))
    (check-not-false (member "preview_diff" tool-names))
    (check-not-false (member "list_dir" tool-names))
    (check-not-false (member "grep_code" tool-names))
    (check-not-false (member "git_status" tool-names))
    (check-not-false (member "git_diff" tool-names))
    (check-not-false (member "git_log" tool-names))
    (check-not-false (member "git_commit" tool-names))
    (check-not-false (member "git_checkout" tool-names)))))

(module+ test
  (require rackunit/text-ui)
  (run-tests acp-tools-tests))
