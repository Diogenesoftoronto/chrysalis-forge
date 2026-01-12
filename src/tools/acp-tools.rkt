#lang racket/base

(provide make-acp-tools execute-acp-tool)
(require json racket/file racket/string racket/system racket/list racket/port racket/match racket/path
         "../stores/eval-store.rkt" "../core/optimizer-gepa.rkt" "mcp-client.rkt" "../llm/openai-client.rkt")

(define mcp-clients (make-hash))
(define mcp-tool-map (make-hash))

(define (register-mcp-server! name command args)
  (define client (mcp-connect name command args))
  (hash-set! mcp-clients name client)
  (for ([t (mcp-client-tools client)])
    (hash-set! mcp-tool-map (hash-ref t 'name) client))
  (format "Connected to MCP server '~a'. Added tools: ~a" 
          name 
          (string-join (map (λ (t) (hash-ref t 'name)) (mcp-client-tools client)) ", ")))

;; Tool definitions for the agent
(define (make-acp-tools)
  (append
  (list
   ;; MCP Tool
   (hash 'type "function"
         'function (hash 'name "add_mcp_server"
                         'description "Connect a new MCP (Model Context Protocol) server to add its tools to the agent."
                         'parameters (hash 'type "object"
                                           'properties (hash 'name (hash 'type "string" 'description "Unique name for the server")
                                                             'command (hash 'type "string" 'description "Executable command (e.g. 'npx', 'python')")
                                                             'args (hash 'type "array" 
                                                                         'items (hash 'type "string")
                                                                         'description "Arguments for the command"))
                                           'required '("name" "command" "args"))))
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
                                           'required '("branch"))))
   ;; Jujutsu (jj) tools - next-gen Git-compatible VCS with easy rollback
   (hash 'type "function"
         'function (hash 'name "jj_status"
                         'description "Get jj status showing current changes and working copy state."
                         'parameters (hash 'type "object"
                                           'properties (hash 'path (hash 'type "string" 'description "Path to repository"))
                                           'required '())))
   (hash 'type "function"
         'function (hash 'name "jj_log"
                         'description "Show jj commit log with graph visualization."
                         'parameters (hash 'type "object"
                                           'properties (hash 'path (hash 'type "string" 'description "Path to repository")
                                                             'count (hash 'type "integer" 'description "Number of commits to show (default 10)"))
                                           'required '())))
   (hash 'type "function"
         'function (hash 'name "jj_diff"
                         'description "Show jj diff of current changes or between revisions."
                         'parameters (hash 'type "object"
                                           'properties (hash 'path (hash 'type "string" 'description "Path to repository")
                                                             'revision (hash 'type "string" 'description "Optional revision to diff"))
                                           'required '())))
   (hash 'type "function"
         'function (hash 'name "jj_undo"
                         'description "Undo the last jj operation. Can undo commits, rebases, etc. Very safe - the undo itself can be undone."
                         'parameters (hash 'type "object"
                                           'properties (hash 'path (hash 'type "string" 'description "Path to repository"))
                                           'required '())))
   (hash 'type "function"
         'function (hash 'name "jj_op_log"
                         'description "Show the operation log - history of all jj operations. Use with jj_op_restore to rollback to any point."
                         'parameters (hash 'type "object"
                                           'properties (hash 'path (hash 'type "string" 'description "Path to repository")
                                                             'count (hash 'type "integer" 'description "Number of operations to show"))
                                           'required '())))
   (hash 'type "function"
         'function (hash 'name "jj_op_restore"
                         'description "Restore repository to a specific operation state. Use jj_op_log to find the operation ID."
                         'parameters (hash 'type "object"
                                           'properties (hash 'path (hash 'type "string" 'description "Path to repository")
                                                             'operation_id (hash 'type "string" 'description "Operation ID from jj_op_log"))
                                           'required '("operation_id"))))
   (hash 'type "function"
         'function (hash 'name "jj_workspace_add"
                         'description "Create a new parallel workspace (like git worktree). Allows working on multiple tasks simultaneously."
                         'parameters (hash 'type "object"
                                           'properties (hash 'path (hash 'type "string" 'description "Base repository path")
                                                             'workspace_path (hash 'type "string" 'description "Path for the new workspace")
                                                             'revision (hash 'type "string" 'description "Optional revision to check out in new workspace"))
                                           'required '("workspace_path"))))
   (hash 'type "function"
         'function (hash 'name "jj_workspace_list"
                         'description "List all workspaces in the repository."
                         'parameters (hash 'type "object"
                                           'properties (hash 'path (hash 'type "string" 'description "Path to repository"))
                                           'required '())))
   (hash 'type "function"
         'function (hash 'name "jj_describe"
                         'description "Set or update the description (commit message) for the current change."
                         'parameters (hash 'type "object"
                                           'properties (hash 'path (hash 'type "string" 'description "Path to repository")
                                                             'message (hash 'type "string" 'description "Commit message/description"))
                                           'required '("message"))))
   (hash 'type "function"
         'function (hash 'name "jj_new"
                         'description "Create a new change (commit). In jj, all changes are automatically tracked."
                         'parameters (hash 'type "object"
                                           'properties (hash 'path (hash 'type "string" 'description "Path to repository")
                                                             'message (hash 'type "string" 'description "Optional description for the new change"))
                                           'required '())))
   ;; Self-evolution and feedback tools
   (hash 'type "function"
         'function (hash 'name "suggest_profile"
                         'description "Get optimal sub-agent profile for a task type based on historical success rates."
                         'parameters (hash 'type "object"
                                           'properties (hash 'task_type (hash 'type "string" 'description "Type of task (e.g. 'file-edit', 'search', 'vcs')"))
                                           'required '("task_type"))))
   (hash 'type "function"
         'function (hash 'name "profile_stats"
                         'description "Get performance statistics for sub-agent profiles. Use to learn which profiles work best."
                         'parameters (hash 'type "object"
                                           'properties (hash 'profile (hash 'type "string" 'description "Optional: specific profile to query"))
                                           'required '())))
   (hash 'type "function"
         'function (hash 'name "evolve_system"
                         'description "Trigger GEPA evolution of the system prompt based on feedback. Self-improvement capability."
                         'parameters (hash 'type "object"
                                           'properties (hash 'feedback (hash 'type "string" 'description "Feedback about what to improve"))
                                           'required '("feedback"))))
   (hash 'type "function"
         'function (hash 'name "log_feedback"
                         'description "Log feedback about a task result for learning. Feeds into profile optimization."
                         'parameters (hash 'type "object"
                                           'properties (hash 'task_id (hash 'type "string" 'description "Task ID")
                                                             'success (hash 'type "boolean" 'description "Whether task succeeded")
                                                             'task_type (hash 'type "string" 'description "Category of task")
                                                             'feedback (hash 'type "string" 'description "Additional feedback"))
                                           'required '("task_id" "success"))))
   (hash 'type "function"
         'function (hash 'name "use_llm_judge"
                         'description "Use an LLM as a judge to evaluate content against specific criteria. Useful for security review, code quality checks, etc."
                         'parameters (hash 'type "object"
                                           'properties (hash 'content (hash 'type "string" 'description "Content to evaluate")
                                                             'criteria (hash 'type "string" 'description "Evaluation criteria or instructions")
                                                             'model (hash 'type "string" 'description "Optional: model to use (e.g. 'gpt-5.2', 'o1-preview'). Defaults to 'gpt-5.2'."))
                                           'required '("content" "criteria"))))
   ;; Dynamic MCP tools
   (flatten
    (for/list ([client (in-hash-values mcp-clients)]
               #:when #t
               [t (mcp-client-tools client)])
      (hash 'type "function"
            'function (hash 'name (hash-ref t 'name)
                            'description (hash-ref t 'description "")
                            'parameters (hash-ref t 'inputSchema (hash 'type "object" 'properties (hash))))))))))

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
      
      ;; Jujutsu (jj) tools
      ["jj_status"
       (run-jj-cmd (hash-ref args 'path ".") "status")]
      
      ["jj_log"
       (define count (hash-ref args 'count 10))
       (run-jj-cmd (hash-ref args 'path ".") "log" "-n" (number->string count))]
      
      ["jj_diff"
       (define rev (hash-ref args 'revision #f))
       (if rev
           (run-jj-cmd (hash-ref args 'path ".") "diff" "-r" rev)
           (run-jj-cmd (hash-ref args 'path ".") "diff"))]
      
      ["jj_undo"
       (if (>= security-level 2)
           (run-jj-cmd (hash-ref args 'path ".") "undo")
           "Permission Denied: Requires security level 2.")]
      
      ["jj_op_log"
       (define count (hash-ref args 'count 10))
       (run-jj-cmd (hash-ref args 'path ".") "op" "log" "-n" (number->string count))]
      
      ["jj_op_restore"
       (if (>= security-level 2)
           (run-jj-cmd (hash-ref args 'path ".") "op" "restore" (hash-ref args 'operation_id))
           "Permission Denied: Requires security level 2.")]
      
      ["jj_workspace_add"
       (if (>= security-level 2)
           (let ([rev (hash-ref args 'revision #f)])
             (if rev
                 (run-jj-cmd (hash-ref args 'path ".") "workspace" "add" (hash-ref args 'workspace_path) "-r" rev)
                 (run-jj-cmd (hash-ref args 'path ".") "workspace" "add" (hash-ref args 'workspace_path))))
           "Permission Denied: Requires security level 2.")]
      
      ["jj_workspace_list"
       (run-jj-cmd (hash-ref args 'path ".") "workspace" "list")]
      
      ["jj_describe"
       (if (>= security-level 2)
           (run-jj-cmd (hash-ref args 'path ".") "describe" "-m" (hash-ref args 'message))
           "Permission Denied: Requires security level 2.")]
      
      ["jj_new"
       (if (>= security-level 2)
           (let ([msg (hash-ref args 'message #f)])
             (if msg
                 (run-jj-cmd (hash-ref args 'path ".") "new" "-m" msg)
                 (run-jj-cmd (hash-ref args 'path ".") "new")))
           "Permission Denied: Requires security level 2.")]
      
      ;; Self-evolution tools
      ["suggest_profile"
       (define-values (profile rate) (suggest-profile (hash-ref args 'task_type)))
       (format "Suggested profile: ~a (success rate: ~a%)" profile (* 100 rate))]
      
      ["profile_stats"
       (define profile (hash-ref args 'profile #f))
       (define stats (get-profile-stats (if profile (string->symbol profile) #f)))
       (if stats (format "~a" stats) "No stats available yet.")]
      
      ["evolve_system"
       (if (>= security-level 2)
           (gepa-evolve! (hash-ref args 'feedback))
           "Permission Denied: Requires security level 2.")]
      
      ["log_feedback"
       (log-eval! #:task-id (hash-ref args 'task_id)
                  #:success? (hash-ref args 'success)
                  #:profile 'unknown
                  #:task-type (hash-ref args 'task_type "unknown")
                  #:feedback (hash-ref args 'feedback ""))
       "Feedback logged for learning."]

      ["use_llm_judge"
       (define content (hash-ref args 'content))
       (define criteria (hash-ref args 'criteria))
       (define model (hash-ref args 'model 
                                (or (getenv "MODEL")
                                    (getenv "CHRYSALIS_DEFAULT_MODEL")
                                    "gpt-5.2")))
       (define sender (make-openai-sender #:model model))
       (define prompt (format "You are an expert judge. Evaluate the following content based on these criteria:\n\nCRITERIA:\n~a\n\nCONTENT:\n~a\n\nProvide a detailed assessment and a final verdict." criteria content))
       (define-values (ok? res usage) (sender prompt))
       (if ok? res (format "Judge Error: ~a" res))]

       ["add_mcp_server"
        (if (>= security-level 2)
            (register-mcp-server! (hash-ref args 'name)
                                  (hash-ref args 'command)
                                  (hash-ref args 'args))
            "Permission Denied: Requires security level 2.")]
      
      [_ 
       (cond
         [(hash-has-key? mcp-tool-map name)
          (define client (hash-ref mcp-tool-map name))
          (mcp-call-tool client name args)]
         [else (format "Unknown tool: ~a" name)])])))

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

;; Helper: Run a jj (Jujutsu) command and capture output
(define (run-jj-cmd path . args)
  (define jj-path (find-executable-path "jj"))
  (unless jj-path (error 'jj "jj (Jujutsu) executable not found. Install from https://martinvonz.github.io/jj/"))
  (parameterize ([current-directory path])
    (define-values (sp stdout stdin stderr) 
      (apply subprocess #f #f #f jj-path args))
    (close-output-port stdin)
    (define output (port->string stdout))
    (define errors (port->string stderr))
    (subprocess-wait sp)
    (define status (subprocess-status sp))
    (close-input-port stdout)
    (close-input-port stderr)
    (if (= status 0)
        output
        (format "jj error (exit ~a): ~a" status errors))))