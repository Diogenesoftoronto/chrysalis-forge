#lang racket/base
(require rackunit
         "../src/tools/acp-tools.rkt")

(provide acp-tools-tests)

(define acp-tools-tests
  (test-suite
   "acp-tools tests"
   
   (test-case
    "make-acp-tools structure"
    (define tools (make-acp-tools))
    (check-pred list? tools)
    (check-equal? (length tools) 25)
    
    ;; Check read_file and write_file
    (define read-tool (car tools))
    (check-equal? (hash-ref (hash-ref read-tool 'function) 'name) "read_file")
    
    (define write-tool (cadr tools))
    (check-equal? (hash-ref (hash-ref write-tool 'function) 'name) "write_file")
    
    ;; Check tools exist by name
    (define tool-names (map (λ (t) (hash-ref (hash-ref t 'function) 'name)) tools))
    ;; File/search tools
    (check-not-false (member "patch_file" tool-names))
    (check-not-false (member "preview_diff" tool-names))
    (check-not-false (member "list_dir" tool-names))
    (check-not-false (member "grep_code" tool-names))
    ;; Git tools
    (check-not-false (member "git_status" tool-names))
    (check-not-false (member "git_diff" tool-names))
    (check-not-false (member "git_log" tool-names))
    (check-not-false (member "git_commit" tool-names))
    (check-not-false (member "git_checkout" tool-names))
    ;; Jujutsu (jj) tools
    (check-not-false (member "jj_status" tool-names))
    (check-not-false (member "jj_log" tool-names))
    (check-not-false (member "jj_undo" tool-names))
    (check-not-false (member "jj_op_restore" tool-names))
    (check-not-false (member "jj_workspace_add" tool-names))
    (check-not-false (member "jj_workspace_list" tool-names)))))

(module+ test
  (require rackunit/text-ui)
  (run-tests acp-tools-tests))
