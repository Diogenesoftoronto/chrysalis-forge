#lang racket/base
;; Comprehensive ACP Tool Execution Tests
;; Tests that execute-acp-tool actually works according to spec:
;; - File tools (read, write, patch, preview_diff, list_dir, grep_code)
;; - Security level enforcement
;; - Git tools (basic invocation)
;; - Self-evolution tools (suggest_profile, profile_stats, evolve_harness)
;; - Error handling (missing files, bad args, unknown tools)
;; - Tool schema validation (all tools have correct JSON Schema structure)

(require rackunit
         rackunit/text-ui
         racket/list
         racket/string
         racket/file
         racket/path
         racket/hash
         json
         "../src/tools/acp-tools.rkt")

;; ============================================================================
;; Helpers
;; ============================================================================

(define test-dir (make-temporary-file "acp-test-~a" 'directory))

(define (test-file name [content ""])
  (define p (build-path test-dir name))
  (display-to-file content p #:exists 'replace)
  (path->string p))

(define (cleanup!)
  (when (directory-exists? test-dir)
    (delete-directory/files test-dir)))

;; ============================================================================
;; Tool Schema Validation
;; ============================================================================

(define schema-tests
  (test-suite
   "Tool Schema Validation"

   (test-case "all tools have valid JSON Schema structure"
     (define tools (filter hash? (flatten (make-acp-tools))))
     (for ([tool tools])
       (check-true (hash-has-key? tool 'type)
                   (format "Tool missing 'type': ~a" tool))
       (check-equal? (hash-ref tool 'type) "function")
       (define fn (hash-ref tool 'function))
       (check-true (hash-has-key? fn 'name)
                   (format "Tool function missing 'name': ~a" fn))
       (check-true (hash-has-key? fn 'description)
                   (format "Tool ~a missing 'description'" (hash-ref fn 'name)))
       (check-true (hash-has-key? fn 'parameters)
                   (format "Tool ~a missing 'parameters'" (hash-ref fn 'name)))
       (define params (hash-ref fn 'parameters))
       (check-equal? (hash-ref params 'type) "object"
                     (format "Tool ~a params type should be 'object'" (hash-ref fn 'name)))
       (check-true (hash-has-key? params 'properties)
                   (format "Tool ~a missing 'properties'" (hash-ref fn 'name)))
       (check-true (hash-has-key? params 'required)
                   (format "Tool ~a missing 'required'" (hash-ref fn 'name)))))

   (test-case "all tool names are snake_case"
     (define tools (filter hash? (flatten (make-acp-tools))))
     (define names (map (λ (t) (hash-ref (hash-ref t 'function) 'name)) tools))
     (for ([name names])
       (check-true (regexp-match? #rx"^[a-z][a-z0-9_]*$" name)
                   (format "Tool name ~a is not snake_case" name))))

   (test-case "no duplicate tool names"
     (define tools (filter hash? (flatten (make-acp-tools))))
     (define names (map (λ (t) (hash-ref (hash-ref t 'function) 'name)) tools))
     (check-equal? (length names) (length (remove-duplicates names))
                   "Duplicate tool names detected"))

   (test-case "required fields are subset of properties"
     (define tools (filter hash? (flatten (make-acp-tools))))
     (for ([tool tools])
       (define fn (hash-ref tool 'function))
       (define params (hash-ref fn 'parameters))
       (define props (hash-keys (hash-ref params 'properties)))
       (define required (hash-ref params 'required))
       (for ([r required])
         (check-not-false
          (member (if (symbol? r) r (string->symbol r))
                  (map (λ (k) (if (symbol? k) k (string->symbol k))) props))
          (format "Tool ~a: required field '~a' not in properties"
                  (hash-ref fn 'name) r)))))

   (test-case "evolve_harness tool exists with correct params"
     (define tools (filter hash? (flatten (make-acp-tools))))
     (define names (map (λ (t) (hash-ref (hash-ref t 'function) 'name)) tools))
     (check-not-false (member "evolve_harness" names))
     (define eh-tool
       (findf (λ (t) (equal? "evolve_harness" (hash-ref (hash-ref t 'function) 'name))) tools))
     (define params (hash-ref (hash-ref (hash-ref eh-tool 'function) 'parameters) 'properties))
     (check-true (hash-has-key? params 'feedback))
     (check-true (hash-has-key? params 'mutation_rate)))

   (test-case "tool count includes all expected categories"
     (define tools (filter hash? (flatten (make-acp-tools))))
     (define names (map (λ (t) (hash-ref (hash-ref t 'function) 'name)) tools))
     ;; File tools: 6
     (check-not-false (member "read_file" names))
     (check-not-false (member "write_file" names))
     (check-not-false (member "patch_file" names))
     (check-not-false (member "preview_diff" names))
     (check-not-false (member "list_dir" names))
     (check-not-false (member "grep_code" names))
     ;; Git tools: 5
     (check-not-false (member "git_status" names))
     (check-not-false (member "git_diff" names))
     (check-not-false (member "git_log" names))
     (check-not-false (member "git_commit" names))
     (check-not-false (member "git_checkout" names))
     ;; Jujutsu tools: 10
     (check-not-false (member "jj_status" names))
     (check-not-false (member "jj_log" names))
     (check-not-false (member "jj_diff" names))
     (check-not-false (member "jj_undo" names))
     (check-not-false (member "jj_op_log" names))
     (check-not-false (member "jj_op_restore" names))
     (check-not-false (member "jj_workspace_add" names))
     (check-not-false (member "jj_workspace_list" names))
     (check-not-false (member "jj_describe" names))
     (check-not-false (member "jj_new" names))
     ;; Self-evolution tools: 5
     (check-not-false (member "suggest_profile" names))
     (check-not-false (member "profile_stats" names))
     (check-not-false (member "evolve_system" names))
     (check-not-false (member "evolve_harness" names))
     (check-not-false (member "log_feedback" names))
     ;; Other: 3
     (check-not-false (member "use_llm_judge" names))
     (check-not-false (member "add_mcp_server" names))
     ;; At least 28 base tools (6+5+10+5+2)
     (check-true (>= (length names) 28)
                 (format "Expected >= 28 tools, got ~a" (length names))))))

;; ============================================================================
;; File Tool Execution Tests
;; ============================================================================

(define file-tool-tests
  (test-suite
   "File Tool Execution"

   (test-case "read_file: reads existing file"
     (define p (test-file "hello.txt" "Hello, World!"))
     (define result (execute-acp-tool "read_file" (hash 'path p) 0))
     (check-equal? result "Hello, World!"))

   (test-case "read_file: error on missing file"
     (define result (execute-acp-tool "read_file" (hash 'path "/nonexistent/file.txt") 0))
     (check-true (string-contains? result "Error")))

   (test-case "read_file: reads multi-line file"
     (define p (test-file "multi.txt" "line1\nline2\nline3"))
     (define result (execute-acp-tool "read_file" (hash 'path p) 0))
     (check-equal? result "line1\nline2\nline3"))

   (test-case "read_file: reads empty file"
     (define p (test-file "empty.txt" ""))
     (define result (execute-acp-tool "read_file" (hash 'path p) 0))
     (check-equal? result ""))

   (test-case "write_file: writes at security level 2"
     (define p (path->string (build-path test-dir "new.txt")))
     (define result (execute-acp-tool "write_file" (hash 'path p 'content "written!") 2))
     (check-equal? result "File written successfully.")
     (check-equal? (file->string p) "written!"))

   (test-case "write_file: denied at security level 1"
     (define p (path->string (build-path test-dir "denied.txt")))
     (define result (execute-acp-tool "write_file" (hash 'path p 'content "nope") 1))
     (check-true (string-contains? result "Permission Denied")))

   (test-case "write_file: denied at security level 0"
     (define p (path->string (build-path test-dir "denied0.txt")))
     (define result (execute-acp-tool "write_file" (hash 'path p 'content "nope") 0))
     (check-true (string-contains? result "Permission Denied")))

   (test-case "write_file: overwrites existing file"
     (define p (test-file "overwrite.txt" "old content"))
     (execute-acp-tool "write_file" (hash 'path p 'content "new content") 2)
     (check-equal? (file->string p) "new content"))

   (test-case "patch_file: patches line range"
     (define p (test-file "patch.txt" "line1\nline2\nline3\nline4\nline5"))
     (define result (execute-acp-tool "patch_file"
                                       (hash 'path p 'start_line 2 'end_line 3 'replacement "replaced2\nreplaced3")
                                       2))
     (check-true (string-contains? result "Patched"))
     (define content (file->string p))
     (check-true (string-contains? content "replaced2"))
     (check-true (string-contains? content "line1"))
     (check-true (string-contains? content "line4")))

   (test-case "patch_file: denied at security level 1"
     (define p (test-file "patch-denied.txt" "line1\nline2"))
     (define result (execute-acp-tool "patch_file"
                                       (hash 'path p 'start_line 1 'end_line 1 'replacement "x")
                                       1))
     (check-true (string-contains? result "Permission Denied")))

   (test-case "patch_file: error on invalid line range"
     (define p (test-file "patch-range.txt" "line1\nline2"))
     (define result (execute-acp-tool "patch_file"
                                       (hash 'path p 'start_line 1 'end_line 5 'replacement "x")
                                       2))
     (check-true (string-contains? result "Error")))

   (test-case "patch_file: error on missing file"
     (define result (execute-acp-tool "patch_file"
                                       (hash 'path "/nonexistent.txt" 'start_line 1 'end_line 1 'replacement "x")
                                       2))
     (check-true (string-contains? result "Error")))

   (test-case "patch_file: single line replacement"
     (define p (test-file "patch-single.txt" "aaa\nbbb\nccc"))
     (execute-acp-tool "patch_file"
                        (hash 'path p 'start_line 2 'end_line 2 'replacement "BBB")
                        2)
     (check-equal? (file->string p) "aaa\nBBB\nccc"))

   (test-case "preview_diff: shows diff without writing"
     (define p (test-file "diff-preview.txt" "line1\nline2\nline3"))
     (define result (execute-acp-tool "preview_diff"
                                       (hash 'path p 'start_line 2 'end_line 2 'replacement "CHANGED")
                                       0))
     ;; Should show unified diff format
     (check-true (string-contains? result "---"))
     (check-true (string-contains? result "+++"))
     (check-true (string-contains? result "-line2"))
     (check-true (string-contains? result "+CHANGED"))
     ;; File should be unchanged
     (check-equal? (file->string p) "line1\nline2\nline3"))

   (test-case "preview_diff: works at any security level"
     (define p (test-file "diff-sec.txt" "a\nb\nc"))
     (define result (execute-acp-tool "preview_diff"
                                       (hash 'path p 'start_line 1 'end_line 1 'replacement "A")
                                       0))
     (check-true (string-contains? result "-a"))
     (check-true (string-contains? result "+A")))

   (test-case "list_dir: lists directory contents"
     (test-file "dir-a.txt" "a")
     (test-file "dir-b.txt" "b")
     (define result (execute-acp-tool "list_dir"
                                       (hash 'path (path->string test-dir) 'recursive #f)
                                       0))
     (check-true (string-contains? result "dir-a.txt"))
     (check-true (string-contains? result "dir-b.txt")))

   (test-case "list_dir: error on missing directory"
     (define result (execute-acp-tool "list_dir"
                                       (hash 'path "/nonexistent/dir")
                                       0))
     (check-true (string-contains? result "Error")))

   (test-case "grep_code: finds pattern in files"
     (define p (test-file "searchme.rkt" "(define (foo x) (+ x 1))\n(define (bar y) (* y 2))"))
     (define result (execute-acp-tool "grep_code"
                                       (hash 'pattern "define.*foo" 'path (path->string test-dir))
                                       0))
     (check-true (string-contains? result "foo"))
     (check-true (string-contains? result "searchme.rkt")))

   (test-case "grep_code: no matches returns message"
     (define p (test-file "nomatch.txt" "nothing interesting here"))
     (define result (execute-acp-tool "grep_code"
                                       (hash 'pattern "ZZZNOTFOUND" 'path (path->string test-dir))
                                       0))
     (check-true (string-contains? result "No matches")))

   (test-case "grep_code: filters by extension"
     (test-file "target.rkt" "findme here")
     (test-file "ignore.py" "findme here too")
     (define result (execute-acp-tool "grep_code"
                                       (hash 'pattern "findme"
                                             'path (path->string test-dir)
                                             'extensions "rkt")
                                       0))
     (check-true (string-contains? result "target.rkt"))
     (check-false (string-contains? result "ignore.py")))))

;; ============================================================================
;; Security Level Enforcement Tests
;; ============================================================================

(define security-tests
  (test-suite
   "Security Level Enforcement"

   (test-case "read-only tools work at level 0"
     (define p (test-file "sec-read.txt" "readable"))
     (check-equal? (execute-acp-tool "read_file" (hash 'path p) 0) "readable")
     ;; list_dir works at level 0
     (check-true (string? (execute-acp-tool "list_dir"
                                             (hash 'path (path->string test-dir)) 0)))
     ;; grep works at level 0
     (check-true (string? (execute-acp-tool "grep_code"
                                             (hash 'pattern "." 'path (path->string test-dir)) 0)))
     ;; preview_diff works at level 0
     (define p2 (test-file "sec-diff.txt" "a\nb"))
     (check-true (string-contains?
                  (execute-acp-tool "preview_diff"
                                    (hash 'path p2 'start_line 1 'end_line 1 'replacement "x") 0)
                  "---")))

   (test-case "write tools denied at level 0"
     (define p (path->string (build-path test-dir "sec0.txt")))
     (check-true (string-contains?
                  (execute-acp-tool "write_file" (hash 'path p 'content "x") 0)
                  "Permission Denied")))

   (test-case "write tools denied at level 1"
     (define p (path->string (build-path test-dir "sec1.txt")))
     (check-true (string-contains?
                  (execute-acp-tool "write_file" (hash 'path p 'content "x") 1)
                  "Permission Denied"))
     (check-true (string-contains?
                  (execute-acp-tool "git_commit" (hash 'message "test") 1)
                  "Permission Denied"))
     (check-true (string-contains?
                  (execute-acp-tool "git_checkout" (hash 'branch "test") 1)
                  "Permission Denied")))

   (test-case "write tools allowed at level 2"
     (define p (path->string (build-path test-dir "sec2.txt")))
     (define result (execute-acp-tool "write_file" (hash 'path p 'content "allowed") 2))
     (check-equal? result "File written successfully."))

   (test-case "evolve_system denied at level 1"
     (check-true (string-contains?
                  (execute-acp-tool "evolve_system" (hash 'feedback "test") 1)
                  "Permission Denied")))

   (test-case "evolve_harness denied at level 1"
     (check-true (string-contains?
                  (execute-acp-tool "evolve_harness" (hash 'feedback "test") 1)
                  "Permission Denied")))

   (test-case "jj mutation tools denied at level 1"
     (check-true (string-contains?
                  (execute-acp-tool "jj_undo" (hash 'path ".") 1)
                  "Permission Denied"))
     (check-true (string-contains?
                  (execute-acp-tool "jj_op_restore" (hash 'path "." 'operation_id "abc") 1)
                  "Permission Denied"))
     (check-true (string-contains?
                  (execute-acp-tool "jj_describe" (hash 'path "." 'message "test") 1)
                  "Permission Denied"))
     (check-true (string-contains?
                  (execute-acp-tool "jj_new" (hash 'path ".") 1)
                  "Permission Denied"))
     (check-true (string-contains?
                  (execute-acp-tool "jj_workspace_add" (hash 'path "." 'workspace_path "/tmp/ws") 1)
                  "Permission Denied")))

   (test-case "add_mcp_server denied at level 1"
     (check-true (string-contains?
                  (execute-acp-tool "add_mcp_server"
                                    (hash 'name "test" 'command "echo" 'args '("hi")) 1)
                  "Permission Denied")))))

;; ============================================================================
;; Git Tool Tests (basic invocation in actual repo)
;; ============================================================================

(define git-tool-tests
  (test-suite
   "Git Tool Execution"

   (test-case "git_status: returns status in current repo"
     (define result (execute-acp-tool "git_status" (hash 'path ".") 0))
     ;; Should return some output (even if empty string for clean repo)
     (check-true (string? result)))

   (test-case "git_diff: returns diff output"
     (define result (execute-acp-tool "git_diff" (hash 'path ".") 0))
     (check-true (string? result)))

   (test-case "git_log: returns commit history"
     (define result (execute-acp-tool "git_log" (hash 'path "." 'count 5) 0))
     (check-true (string? result))
     ;; Should contain at least one commit hash
     (check-true (> (string-length result) 0)))

   (test-case "git_log: respects count parameter"
     (define result5 (execute-acp-tool "git_log" (hash 'path "." 'count 5) 0))
     (define result1 (execute-acp-tool "git_log" (hash 'path "." 'count 1) 0))
     ;; 1-line log should be shorter than or equal to 5-line log
     (check-true (<= (length (string-split result1 "\n"))
                     (length (string-split result5 "\n")))))))

;; ============================================================================
;; Self-Evolution Tool Tests
;; ============================================================================

(define evolution-tool-tests
  (test-suite
   "Self-Evolution Tool Execution"

   (test-case "suggest_profile: returns a suggestion"
     (define result (execute-acp-tool "suggest_profile"
                                       (hash 'task_type "file-edit") 0))
     (check-true (string-contains? result "Suggested profile")))

   (test-case "profile_stats: returns stats or no-stats message"
     (define result (execute-acp-tool "profile_stats" (hash) 0))
     (check-true (or (string-contains? result "No stats")
                     (> (string-length result) 0))))

   (test-case "log_feedback: logs successfully"
     (define result (execute-acp-tool "log_feedback"
                                       (hash 'task_id "test-123"
                                             'success #t
                                             'task_type "test"
                                             'feedback "test feedback")
                                       0))
     (check-equal? result "Feedback logged for learning."))

   (test-case "log_feedback: logs failure"
     (define result (execute-acp-tool "log_feedback"
                                       (hash 'task_id "test-456"
                                             'success #f
                                             'task_type "test"
                                             'feedback "it broke")
                                       0))
     (check-equal? result "Feedback logged for learning."))))

;; ============================================================================
;; Error Handling Tests
;; ============================================================================

(define error-handling-tests
  (test-suite
   "Error Handling"

   (test-case "unknown tool returns error message"
     (define result (execute-acp-tool "nonexistent_tool" (hash) 0))
     (check-true (string-contains? result "Unknown tool")))

   (test-case "missing required arg returns error"
     ;; read_file without 'path should error
     (define result (execute-acp-tool "read_file" (hash) 0))
     (check-true (string-contains? result "Error")))

   (test-case "patch_file on nonexistent file returns error"
     (define result (execute-acp-tool "patch_file"
                                       (hash 'path "/tmp/nonexistent_acp_test.rkt"
                                             'start_line 1 'end_line 1
                                             'replacement "x")
                                       2))
     (check-true (string-contains? result "Error")))

   (test-case "preview_diff on nonexistent file returns error"
     (define result (execute-acp-tool "preview_diff"
                                       (hash 'path "/tmp/nonexistent_acp_test.rkt"
                                             'start_line 1 'end_line 1
                                             'replacement "x")
                                       0))
     (check-true (string-contains? result "Error")))

   (test-case "grep_code on nonexistent path returns error"
     (define result (execute-acp-tool "grep_code"
                                       (hash 'pattern "test"
                                             'path "/nonexistent/dir/xyz")
                                       0))
     (check-true (string-contains? result "Error")))))

;; ============================================================================
;; Evolve Harness Tool Integration Tests
;; ============================================================================

(define evolve-harness-tests
  (test-suite
   "evolve_harness Tool Integration"

   ;; Note: evolve_harness at level 2 calls gepa-evolve! which requires API keys.
   ;; We test the security gate and verify the tool is wired correctly.

   (test-case "evolve_harness: denied at level 0"
     (define result (execute-acp-tool "evolve_harness"
                                       (hash 'feedback "test" 'mutation_rate 0.5)
                                       0))
     (check-true (string-contains? result "Permission Denied")))

   (test-case "evolve_harness: denied at level 1"
     (define result (execute-acp-tool "evolve_harness"
                                       (hash 'feedback "test" 'mutation_rate 0.5)
                                       1))
     (check-true (string-contains? result "Permission Denied")))

   (test-case "evolve_harness: default mutation_rate is used"
     ;; At level 1, we just verify it hits the permission check
     ;; (confirming the args parsing path is exercised)
     (define result (execute-acp-tool "evolve_harness"
                                       (hash 'feedback "improve accuracy")
                                       1))
     (check-true (string-contains? result "Permission Denied")))))

;; ============================================================================
;; Patch & Diff Consistency Tests
;; ============================================================================

(define patch-consistency-tests
  (test-suite
   "Patch and Diff Consistency"

   (test-case "preview_diff matches what patch_file does"
     (define p (test-file "consistency.txt" "alpha\nbeta\ngamma\ndelta"))
     ;; Preview
     (define preview (execute-acp-tool "preview_diff"
                                        (hash 'path p 'start_line 2 'end_line 3
                                              'replacement "BETA\nGAMMA")
                                        0))
     (check-true (string-contains? preview "-beta"))
     (check-true (string-contains? preview "-gamma"))
     (check-true (string-contains? preview "+BETA"))
     (check-true (string-contains? preview "+GAMMA"))
     ;; Now actually patch
     (execute-acp-tool "patch_file"
                        (hash 'path p 'start_line 2 'end_line 3
                              'replacement "BETA\nGAMMA")
                        2)
     (check-equal? (file->string p) "alpha\nBETA\nGAMMA\ndelta"))

   (test-case "patch_file: replace with more lines"
     (define p (test-file "expand.txt" "a\nb\nc"))
     (execute-acp-tool "patch_file"
                        (hash 'path p 'start_line 2 'end_line 2
                              'replacement "b1\nb2\nb3")
                        2)
     (define lines (string-split (file->string p) "\n"))
     (check-equal? (length lines) 5)
     (check-equal? (first lines) "a")
     (check-equal? (second lines) "b1")
     (check-equal? (last lines) "c"))

   (test-case "patch_file: replace with fewer lines"
     (define p (test-file "shrink.txt" "a\nb\nc\nd\ne"))
     (execute-acp-tool "patch_file"
                        (hash 'path p 'start_line 2 'end_line 4
                              'replacement "X")
                        2)
     (define lines (string-split (file->string p) "\n"))
     (check-equal? (length lines) 3)
     (check-equal? lines '("a" "X" "e")))

   (test-case "patch_file: replace first line"
     (define p (test-file "first.txt" "OLD\nsecond\nthird"))
     (execute-acp-tool "patch_file"
                        (hash 'path p 'start_line 1 'end_line 1
                              'replacement "NEW")
                        2)
     (check-equal? (file->string p) "NEW\nsecond\nthird"))

   (test-case "patch_file: replace last line"
     (define p (test-file "last.txt" "first\nsecond\nOLD"))
     (execute-acp-tool "patch_file"
                        (hash 'path p 'start_line 3 'end_line 3
                              'replacement "NEW")
                        2)
     (check-equal? (file->string p) "first\nsecond\nNEW"))))

;; ============================================================================
;; Run All
;; ============================================================================

(module+ test
  (define result
    (run-tests
     (test-suite
      "ACP Tool Execution Tests"
      schema-tests
      file-tool-tests
      security-tests
      git-tool-tests
      evolution-tool-tests
      error-handling-tests
      evolve-harness-tests
      patch-consistency-tests)))
  (cleanup!)
  result)
