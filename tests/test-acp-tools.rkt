#lang racket/base
(require rackunit
         racket/list
         "../src/tools/acp-tools.rkt")

(provide acp-tools-tests)

(define acp-tools-tests
  (test-suite
   "acp-tools tests"
   
   (test-case
    "make-acp-tools structure"
    (define raw-tools (make-acp-tools))
    (check-pred list? raw-tools)
    ;; Filter to only valid hash tools (ignores empty lists from dynamic MCP)
    (define tools (filter hash? (flatten raw-tools)))
    (check-true (>= (length tools) 25) "Should have at least 25 base tools")
    
    ;; Check tools exist by name (order-independent)
    (define tool-names (map (λ (t) (hash-ref (hash-ref t 'function) 'name)) tools))
    
    ;; Core file tools must exist
    (check-not-false (member "read_file" tool-names))
    (check-not-false (member "write_file" tool-names))
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
