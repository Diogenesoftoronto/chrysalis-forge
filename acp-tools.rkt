#lang racket/base

(provide make-acp-tools execute-acp-tool)
(require json racket/file racket/string racket/system racket/list racket/port racket/match racket/path)

;; Tool definitions for the agent
(define (make-acp-tools)
  (list
   ;; File tools
   (hash 'type "function"
         'function (hash 'name "read_file"
                         'description "Read the contents of a file at the given path."
                         'parameters (hash 'type "object"
                                           'properties (hash 'path (hash 'type "string" 'description "Absolute path to file"))
                                           'required '("path"))))
   (hash 'type "function"
         'function (hash 'name "write_file"
                         'description "Write content to a file, replacing it entirely."
                         'parameters (hash 'type "object"
                                           'properties (hash 'path (hash 'type "string" 'description "Absolute path to file")
                                                             'content (hash 'type "string" 'description "Content to write"))
                                           'required '("path" "content"))))
   (hash 'type "function"
         'function (hash 'name "patch_file"
                         'description "Replace a specific line range in a file with new content. Use this instead of write_file for targeted edits."
                         'parameters (hash 'type "object"
                                           'properties (hash 'path (hash 'type "string" 'description "Absolute path to file")
                                                             'start_line (hash 'type "integer" 'description "1-indexed start line (inclusive)")
                                                             'end_line (hash 'type "integer" 'description "1-indexed end line (inclusive)")
                                                             'replacement (hash 'type "string" 'description "New content to insert (can be multiple lines)"))
                                           'required '("path" "start_line" "end_line" "replacement"))))
   (hash 'type "function"
         'function (hash 'name "preview_diff"
                         'description "Show unified diff of what patch_file would do WITHOUT actually writing. Use to review changes before applying."
                         'parameters (hash 'type "object"
                                           'properties (hash 'path (hash 'type "string" 'description "Absolute path to file")
                                                             'start_line (hash 'type "integer" 'description "1-indexed start line")
                                                             'end_line (hash 'type "integer" 'description "1-indexed end line")
                                                             'replacement (hash 'type "string" 'description "New content"))
                                           'required '("path" "start_line" "end_line" "replacement"))))
   ;; Directory/search tools
   (hash 'type "function"
         'function (hash 'name "list_dir"
                         'description "List files and directories at the given path."
                         'parameters (hash 'type "object"
                                           'properties (hash 'path (hash 'type "string" 'description "Absolute path to directory")
                                                             'recursive (hash 'type "boolean" 'description "If true, list recursively (default false)"))
                                           'required '("path"))))
   (hash 'type "function"
         'function (hash 'name "grep_code"
                         'description "Search for a pattern in files. Returns matching lines with file paths and line numbers."
                         'parameters (hash 'type "object"
                                           'properties (hash 'pattern (hash 'type "string" 'description "Regex pattern to search for")
                                                             'path (hash 'type "string" 'description "Directory or file to search in")
                                                             'extensions (hash 'type "string" 'description "Comma-separated file extensions to include (e.g. \"rkt,scm\")"))
                                           'required '("pattern" "path"))))
   ;; Git tools
   (hash 'type "function"
         'function (hash 'name "git_status"
                         'description "Get git status of the repository (porcelain format)."
                         'parameters (hash 'type "object"
                                           'properties (hash 'path (hash 'type "string" 'description "Path to repository (defaults to cwd)"))
                                           'required '())))
   (hash 'type "function"
         'function (hash 'name "git_diff"
                         'description "Get git diff for a file or entire repository."
                         'parameters (hash 'type "object"
                                           'properties (hash 'path (hash 'type "string" 'description "Path to repository")
                                                             'file (hash 'type "string" 'description "Optional specific file to diff"))
                                           'required '())))
   (hash 'type "function"
         'function (hash 'name "git_log"
                         'description "Get recent git commits."
                         'parameters (hash 'type "object"
                                           'properties (hash 'path (hash 'type "string" 'description "Path to repository")
                                                             'count (hash 'type "integer" 'description "Number of commits to show (default 10)"))
                                           'required '())))
   (hash 'type "function"
         'function (hash 'name "git_commit"
                         'description "Stage all changes and commit with a message. Requires security level 2+."
                         'parameters (hash 'type "object"
                                           'properties (hash 'path (hash 'type "string" 'description "Path to repository")
                                                             'message (hash 'type "string" 'description "Commit message"))
                                           'required '("message"))))
   (hash 'type "function"
         'function (hash 'name "git_checkout"
                         'description "Switch to a different branch or create a new one."
                         'parameters (hash 'type "object"
                                           'properties (hash 'path (hash 'type "string" 'description "Path to repository")
                                                             'branch (hash 'type "string" 'description "Branch name")
                                                             'create (hash 'type "boolean" 'description "If true, create the branch (-b flag)"))
                                           'required '("branch"))))))

;; Execute a tool by name
(define (execute-acp-tool name args security-level)
  (with-handlers ([exn:fail? (λ (e) (format "Tool Error: ~a" (exn-message e)))])
    (match name
      ["read_file"
       (define path (hash-ref args 'path))
       (if (file-exists? path)
           (file->string path)
           (format "Error: File not found: ~a" path))]
      
      ["write_file"
       (if (>= security-level 2)
           (begin
             (display-to-file (hash-ref args 'content) (hash-ref args 'path) #:exists 'replace)
             "File written successfully.")
           "Permission Denied: Requires security level 2.")]
      
      ["patch_file"
       (if (>= security-level 2)
           (patch-file-impl (hash-ref args 'path)
                            (hash-ref args 'start_line)
                            (hash-ref args 'end_line)
                            (hash-ref args 'replacement))
           "Permission Denied: Requires security level 2.")]
      
      ["preview_diff"
       (preview-diff-impl (hash-ref args 'path)
                          (hash-ref args 'start_line)
                          (hash-ref args 'end_line)
                          (hash-ref args 'replacement))]
      
      ["list_dir"
       (define path (hash-ref args 'path))
       (define recursive? (hash-ref args 'recursive #f))
       (if (directory-exists? path)
           (list-dir-impl path recursive?)
           (format "Error: Directory not found: ~a" path))]
      
      ["grep_code"
       (grep-code-impl (hash-ref args 'pattern)
                       (hash-ref args 'path)
                       (hash-ref args 'extensions ""))]
      
      ;; Git tools
      ["git_status"
       (run-git-cmd (hash-ref args 'path ".") "status" "--porcelain")]
      
      ["git_diff"
       (define file (hash-ref args 'file #f))
       (if file
           (run-git-cmd (hash-ref args 'path ".") "diff" file)
           (run-git-cmd (hash-ref args 'path ".") "diff"))]
      
      ["git_log"
       (define count (hash-ref args 'count 10))
       (run-git-cmd (hash-ref args 'path ".") "log" (format "-n~a" count) "--oneline")]
      
      ["git_commit"
       (if (>= security-level 2)
           (begin
             (run-git-cmd (hash-ref args 'path ".") "add" "-A")
             (run-git-cmd (hash-ref args 'path ".") "commit" "-m" (hash-ref args 'message)))
           "Permission Denied: Requires security level 2.")]
      
      ["git_checkout"
       (if (>= security-level 2)
           (if (hash-ref args 'create #f)
               (run-git-cmd (hash-ref args 'path ".") "checkout" "-b" (hash-ref args 'branch))
               (run-git-cmd (hash-ref args 'path ".") "checkout" (hash-ref args 'branch)))
           "Permission Denied: Requires security level 2.")]
      
      [_ (format "Unknown tool: ~a" name)])))

;; Implementation: Patch a file at specific line range
(define (patch-file-impl path start-line end-line replacement)
  (unless (file-exists? path)
    (error 'patch_file "File not found: ~a" path))
  (define lines (file->lines path))
  (define total (length lines))
  (unless (and (>= start-line 1) (<= end-line total) (<= start-line end-line))
    (error 'patch_file "Invalid line range ~a-~a (file has ~a lines)" start-line end-line total))
  (define before (take lines (sub1 start-line)))
  (define after (drop lines end-line))
  (define new-lines (append before (string-split replacement "\n") after))
  (display-to-file (string-join new-lines "\n") path #:exists 'replace)
  (format "Patched lines ~a-~a in ~a" start-line end-line path))

;; Implementation: List directory contents
(define (list-dir-impl path recursive?)
  (define (format-entry p)
    (define name (path->string (file-name-from-path p)))
    (cond
      [(directory-exists? p) (string-append name "/")]
      [else name]))
  (define entries
    (if recursive?
        (for/list ([p (in-directory path)]) (path->string p))
        (map (λ (f) (format-entry (build-path path f))) (directory-list path))))
  (string-join entries "\n"))

;; Implementation: Search for pattern in files
(define (grep-code-impl pattern path extensions)
  (define ext-list (if (string=? extensions "") '() (string-split extensions ",")))
  (define rx (regexp pattern))
  (define results '())
  
  (define (search-file fpath)
    (when (or (null? ext-list)
              (member (path-get-extension fpath) (map (λ (e) (string->bytes/utf-8 (string-append "." e))) ext-list)))
      (define lines (with-handlers ([exn:fail? (λ (_) '())]) (file->lines (path->string fpath))))
      (for ([line lines] [i (in-naturals 1)])
        (when (regexp-match? rx line)
          (set! results (cons (format "~a:~a: ~a" (path->string fpath) i line) results))))))
  
  (cond
    [(file-exists? path) (search-file (string->path path))]
    [(directory-exists? path)
     (for ([p (in-directory path)])
       (when (file-exists? p) (search-file p)))]
    [else (set! results (list (format "Error: Path not found: ~a" path)))])
  
  (if (null? results)
      "No matches found."
      (string-join (reverse results) "\n")))

;; Implementation: Preview diff (show what patch_file would do without writing)
(define (preview-diff-impl path start-line end-line replacement)
  (unless (file-exists? path)
    (error 'preview_diff "File not found: ~a" path))
  (define lines (file->lines path))
  (define total (length lines))
  (unless (and (>= start-line 1) (<= end-line total) (<= start-line end-line))
    (error 'preview_diff "Invalid line range ~a-~a (file has ~a lines)" start-line end-line total))
  (define old-content (string-join (take (drop lines (sub1 start-line)) (- end-line (sub1 start-line))) "\n"))
  (define new-content replacement)
  ;; Generate simple unified diff
  (string-append
   (format "--- ~a (original)\n+++ ~a (modified)\n@@ -~a,~a +~a,~a @@\n"
           path path
           start-line (- end-line (sub1 start-line))
           start-line (length (string-split new-content "\n")))
   (string-join (map (λ (l) (string-append "-" l)) (string-split old-content "\n")) "\n")
   "\n"
   (string-join (map (λ (l) (string-append "+" l)) (string-split new-content "\n")) "\n")))

;; Helper: Run a git command and capture output
(define (run-git-cmd path . args)
  (define git-path (find-executable-path "git"))
  (unless git-path (error 'git "git executable not found"))
  (parameterize ([current-directory path])
    (define-values (sp stdout stdin stderr) 
      (apply subprocess #f #f #f git-path args))
    (close-output-port stdin)
    (define output (port->string stdout))
    (define errors (port->string stderr))
    (subprocess-wait sp)
    (define status (subprocess-status sp))
    (close-input-port stdout)
    (close-input-port stderr)
    (if (= status 0)
        output
        (format "Git error (exit ~a): ~a" status errors))))