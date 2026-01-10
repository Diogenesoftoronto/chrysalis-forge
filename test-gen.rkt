#lang racket/base
(provide make-test-gen-tools test-gen-execute)
(require json racket/file racket/string racket/format racket/path)

;; Test generation tool definitions
(define (make-test-gen-tools)
  (list
   (hash 'type "function"
         'function (hash 'name "generate_tests"
                         'description "Generate tests for code using the LLM. Works with any programming language - the LLM infers the appropriate test framework."
                         'parameters (hash 'type "object"
                                           'properties (hash 'path (hash 'type "string" 'description "Path to the source file to generate tests for")
                                                             'framework (hash 'type "string" 'description "Optional: specific test framework (e.g. pytest, jest, rackunit)")
                                                             'output_path (hash 'type "string" 'description "Optional: path to write generated tests"))
                                           'required '("path"))))))

;; Execute test generation - returns a prompt for the LLM to process
;; The actual generation happens via the LLM, this just builds the prompt
(define (test-gen-execute args api-key send-fn)
  (define path (hash-ref args 'path))
  (define framework (hash-ref args 'framework #f))
  (define output-path (hash-ref args 'output_path #f))
  
  (unless (file-exists? path)
    (error 'generate_tests "File not found: ~a" path))
  
  (define code (file->string path))
  (define ext (path-get-extension (string->path path)))
  
  ;; Build prompt for the LLM
  (define prompt
    (string-append
     "Generate comprehensive tests for the following code.\n\n"
     (if framework
         (format "Use the ~a testing framework.\n\n" framework)
         (format "Infer the appropriate testing framework based on the file extension (~a).\n\n" (or ext "unknown")))
     "Requirements:\n"
     "- Cover all public functions/methods\n"
     "- Include edge cases and error conditions\n"
     "- Use descriptive test names\n"
     "- Include setup/teardown if needed\n\n"
     "Source code:\n```\n" code "\n```\n\n"
     "Generate ONLY the test code, no explanation. Output format: complete, runnable test file."))
  
  ;; If send-fn is provided, use it to call the LLM
  (if send-fn
      (let-values ([(ok? response meta) (send-fn prompt)])
        (if ok?
            (if output-path
                (begin
                  (display-to-file response output-path #:exists 'replace)
                  (format "Tests written to: ~a" output-path))
                response)
            (format "Test generation failed: ~a" response)))
      ;; If no send-fn, return the prompt (agent will handle it)
      prompt))
