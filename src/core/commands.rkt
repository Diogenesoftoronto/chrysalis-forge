#lang racket/base
(require racket/match
         racket/string
         racket/list
         racket/format
         racket/date
         racket/system
         racket/file
         json
         "../llm/dspy-core.rkt"
         "../stores/context-store.rkt"
         "../stores/thread-store.rkt"
         "../stores/rollback-store.rkt"
         "../stores/session-stats.rkt"
         "../core/workflow-engine.rkt"
         "../tools/lsp-client.rkt"
         "../tools/mcp-client.rkt"
         "../llm/model-registry.rkt"
         "../stores/eval-store.rkt"
         "./runtime.rkt"
         "./command-queue.rkt"
         "./repl.rkt"
         "../utils/debug.rkt"
         "../utils/session-summary-viz.rkt"
         "../utils/message-boxes.rkt")

(provide handle-slash-command
         create-new-session!
         resume-last-session!
         resume-session-by-id!
         list-sessions!
         list-threads!
         display-figlet-banner
         print-session-summary!
         handle-new-session)

(define (handle-new-session sid mode)
  (save-ctx! (let ([db (load-ctx)]) 
               (hash-set db 'items 
                         (hash-set (hash-ref db 'items) 
                                   (hash-ref db 'active) 
                                   (struct-copy Ctx (ctx-get-active) [mode (string->symbol mode)]))))))

(define (create-new-session! [mode "code"])
  (define session-id (generate-session-id))
  (define session-name (string->symbol (format "session-~a" session-id)))
  (session-create! session-name (string->symbol mode) #:id session-id)
  (session-switch! session-name)
  session-id)

(define (resume-last-session!)
  (define last-id (session-get-last))
  (if last-id
      (begin
        (session-resume-by-id last-id)
        last-id)
      (create-new-session!)))

(define (resume-session-by-id! session-id)
  (define resumed-name (session-resume-by-id session-id))
  (if resumed-name
      session-id
      (error (format "Session not found: ~a" session-id))))

(define (list-sessions!)
  (define sessions (session-list-with-metadata))
  (if (null? sessions)
      (printf "No sessions found.\n")
      (begin
        (printf "\nSessions:\n")
        (printf "~a\n" (make-string 80 #\-))
        (for ([s sessions])
          (define id (hash-ref s 'id))
          (define title (hash-ref s 'title))
          (define created (hash-ref s 'created_at))
          (define is-active (hash-ref s 'is_active))
          (define created-str (if created
                                  (date->string (seconds->date created) #t)
                                  "Unknown"))
          (printf "~a ~a\n" (if is-active "*" " ") id)
          (when title
            (printf "    Title: ~a\n" title))
          (printf "    Created: ~a\n" created-str)
          (printf "\n"))
        (printf "Use 'chrysalis --session resume' to resume the last session.\n")
        (printf "Use 'chrysalis --session <id>' to resume a specific session.\n"))))

(define (list-threads!)
  (define threads (local-thread-list))
  (define active (local-thread-get-active))
  (if (null? threads)
      (printf "No threads found. Use '/thread new <title>' to create one.\n")
      (begin
        (printf "\nThreads:\n")
        (printf "~a\n" (make-string 80 #\-))
        (for ([t threads])
          (define id (hash-ref t 'id))
          (define title (hash-ref t 'title))
          (define status (hash-ref t 'status))
          (define updated (hash-ref t 'updated_at))
          (define is-active (equal? id active))
          (define updated-str (if updated
                                  (date->string (seconds->date updated) #t)
                                  "Unknown"))
          (printf "~a ~a\n" (if is-active "*" " ") id)
          (when title
            (printf "    Title: ~a\n" title))
          (printf "    Status: ~a | Updated: ~a\n" status updated-str)
          (printf "\n"))
        (printf "Use '/thread switch <id>' to switch threads.\n")
        (printf "Use '/thread continue' to create a continuation thread.\n"))))

(define (display-figlet-banner text font)
  (define figlet-path (find-executable-path "figlet"))
  (if figlet-path
      (let ([cmd (list figlet-path "-f" font text)])
        (with-handlers ([exn:fail? (λ (e) (displayln text))])
          (define-values (sp stdout stdin stderr)
            (apply subprocess (current-output-port) #f (current-error-port) cmd))
          (subprocess-wait sp)
          (define exit-code (subprocess-status sp))
          (when (not (equal? exit-code 0))
            (displayln text))))
      (displayln text)))

(define (print-session-summary!)
  (define duration (- (current-seconds) session-start-time))
  (define total-tokens (+ session-input-tokens session-output-tokens))
  
  (define primary-model
    (if (hash-empty? session-model-usage)
        (model-param)
        (car (argmax (λ (p) (hash-ref (cdr p) 'calls 0))
                     (hash->list session-model-usage)))))
  
  (define tool-usage-sym
    (for/hasheq ([(k v) (in-hash session-tool-usage)])
      (values (if (symbol? k) k (string->symbol (~a k))) v)))
  
  (define stats
    (hasheq 'session-id (or (session-get-last) "unknown")
            'model (~a primary-model)
            'total-cost total-session-cost
            'total-tokens total-tokens
            'input-tokens session-input-tokens
            'output-tokens session-output-tokens
            'duration-seconds duration
            'tool-usage tool-usage-sym
            'token-history '()))
  
  (newline)
  (render-session-summary stats))

(define (handle-slash-command cmd input #:run-turn [run-turn #f] #:fetch-models [fetch-models #f])
  (with-handlers ([exn:fail? (λ (e)
                               (error-box (exn-message e)
                                          #:title "Command Failed"
                                          #:suggestions '("Type /help for available commands")))])
    (match cmd
      [(or "exit" "quit") (print-session-summary!) (displayln "Goodbye.") (exit)]
      ["help" (displayln "Commands:
  /help              - Show this message
  /exit, /quit       - Exit
  /stats             - Show session stats (tokens, cost, context)
  /context           - Show detailed context usage
  /undo <path>       - Rollback file to previous version
  /rollbacks [path]  - List available rollbacks
  /raco <args>       - Run raco commands
  /config list       - List current config
  /config <key> <val> - Set param
  /models            - List available models from API
  /session list|new|switch - Manage sessions
  /thread list|new|switch  - Manage threads
  /workflows         - List workflows
  /lsp [list|start|stop|status] - Manage LSP servers
  /init              - Initialize project agents.md
  /history           - View previous commands
  /history <n>       - Re-run command number n
  /queue             - List queued tasks
  /queue <task>      - Add task to queue
  /queue clear       - Clear all queued tasks
  /queue pop         - Remove next queued task

Tip: Use ↑/↓ arrow keys to navigate command history.")]
      ["raco"
       (if (>= (string-length input) 6)
           (system (format "raco ~a" (substring input 6)))
           (displayln "Usage: /raco <args>"))]
      ["config"
       (define rest (if (>= (string-length input) 8)
                        (string-trim (substring input 8))
                        ""))
       (define parts (if (> (string-length rest) 0)
                         (string-split rest)
                         '()))
       (cond
         [(null? parts)
          (displayln "Usage: /config list  OR  /config <key> <value>")]
         [(and (= (length parts) 1) (equal? (first parts) "list"))
          (printf "Current Configuration:\n")
          (printf "  Model: ~a\n" (model-param))
          (printf "  Vision Model: ~a\n" (vision-model-param))
          (printf "  Judge Model: ~a\n" (llm-judge-model-param))
          (printf "  Base URL: ~a\n" (base-url-param))
          (printf "  Budget: ~a\n" (if (= (budget-param) +inf.0) "unlimited" (budget-param)))
          (printf "  Timeout: ~a\n" (if (= (timeout-param) +inf.0) "unlimited" (timeout-param)))
          (printf "  Priority: ~a\n" (priority-param))
          (printf "  Security Level: ~a\n" (current-security-level))
          (printf "  LLM Judge: ~a\n" (if (llm-judge-param) "ENABLED" "DISABLED"))
          (printf "  API Key: ~a\n"
                  (if env-api-key
                      (let ([len (string-length env-api-key)])
                        (if (> len 12)
                            (format "~a...~a" (substring env-api-key 0 8) (substring env-api-key (- len 4)))
                            (format "~a..." (substring env-api-key 0 (min 4 len)))))
                      "NOT SET"))
          (printf "  Interactive: ~a\n" (if (interactive-param) "YES" "NO"))
          (printf "  Pretty: ~a\n" (pretty-param))]
         [(= (length parts) 2)
          (define key (first parts))
          (define valid-keys '("model" "vision-model" "judge-model" "budget" "priority"))
          (match key
            ["model" (model-param (second parts)) (printf "Model set to ~a\n" (second parts))]
            ["vision-model" (vision-model-param (second parts)) (printf "Vision Model set to ~a\n" (second parts))]
            ["judge-model" (llm-judge-model-param (second parts)) (printf "Judge Model set to ~a\n" (second parts))]
            ["budget" (budget-param (string->number (second parts))) (printf "Budget set to ~a\n" (second parts))]
            ["priority"
             (save-ctx! (let ([db (load-ctx)]) (hash-set db 'items (hash-set (hash-ref db 'items) (hash-ref db 'active) (struct-copy Ctx (ctx-get-active) [priority (string->symbol (second parts))])))))
             (printf "Priority set to ~a\n" (second parts))]
            [_
             (define suggestions (filter (λ (k) (<= (levenshtein key k) 2)) valid-keys))
             (if (not (null? suggestions))
                 (printf "Unknown config key: ~a\nDid you mean: ~a?\n" key (string-join suggestions ", "))
                 (printf "Unknown config key: ~a\nValid keys: ~a\n" key (string-join valid-keys ", ")))])]
         [else (displayln "Usage: /config list  OR  /config <key> <value>")])]

      ["judge"
       (llm-judge-param (not (llm-judge-param)))
       (printf "LLM Security Judge: ~a\n" (if (llm-judge-param) "ENABLED" "DISABLED"))]

      ["session"
       (define rest (if (>= (string-length input) 8)
                        (string-trim (substring input 8))
                        ""))
       (define parts (if (> (string-length rest) 0)
                         (string-split rest)
                         '()))
       (if (>= (length parts) 1)
           (match (first parts)
             ["list" (list-sessions!)]
             ["new"
              (if (= (length parts) 2)
                  (with-handlers ([exn:fail? (λ (e) (printf "Error: ~a\n" (exn-message e)))])
                    (session-create! (second parts))
                    (session-switch! (second parts))
                    (printf "Session context created and switched to '~a'.\n" (second parts)))
                  (displayln "Usage: /session new <name>"))]
             ["switch"
              (if (= (length parts) 2)
                  (with-handlers ([exn:fail? (λ (e) (printf "Error: ~a\n" (exn-message e)))])
                    (session-switch! (second parts))
                    (printf "Switched to session '~a'.\n" (second parts)))
                  (displayln "Usage: /session switch <name>"))]
             ["delete"
              (if (= (length parts) 2)
                  (with-handlers ([exn:fail? (λ (e) (printf "Error: ~a\n" (exn-message e)))])
                    (session-delete! (second parts))
                    (printf "Deleted session '~a'.\n" (second parts)))
                  (displayln "Usage: /session delete <name>"))]
             [_ (displayln "Unknown session command. Try list, new, switch, delete.")])
           (displayln "Usage: /session <list|new|switch|delete> ..."))]

      ["thread"
       (define rest (if (>= (string-length input) 8)
                        (string-trim (substring input 8))
                        ""))
       (define parts (if (> (string-length rest) 0)
                         (string-split rest)
                         '()))
       (if (>= (length parts) 1)
           (match (first parts)
             ["list" (list-threads!)]
             ["new"
              (define title (if (>= (length parts) 2)
                                (string-join (cdr parts) " ")
                                #f))
              (with-handlers ([exn:fail? (λ (e) (printf "Error: ~a\n" (exn-message e)))])
                (define id (local-thread-create! (or title "Untitled")))
                (local-thread-switch! id)
                (printf "Created and switched to thread: ~a\n" id))]
             ["switch"
              (if (>= (length parts) 2)
                  (with-handlers ([exn:fail? (λ (e) (printf "Error: ~a\n" (exn-message e)))])
                    (local-thread-switch! (second parts))
                    (printf "Switched to thread: ~a\n" (second parts)))
                  (displayln "Usage: /thread switch <id>"))]
             ["continue"
              (define current (local-thread-get-active))
              (if current
                  (with-handlers ([exn:fail? (λ (e) (printf "Error: ~a\n" (exn-message e)))])
                    (define title (if (>= (length parts) 2)
                                      (string-join (cdr parts) " ")
                                      #f))
                    (define new-id (local-thread-continue! current #:title title))
                    (local-thread-switch! new-id)
                    (printf "Created continuation thread: ~a\n" new-id))
                  (displayln "No active thread to continue from."))]
             ["child"
              (define current (local-thread-get-active))
              (if (and current (>= (length parts) 2))
                  (with-handlers ([exn:fail? (λ (e) (printf "Error: ~a\n" (exn-message e)))])
                    (define title (string-join (cdr parts) " "))
                    (define new-id (local-thread-spawn-child! current title))
                    (local-thread-switch! new-id)
                    (printf "Created child thread: ~a\n" new-id))
                  (displayln "Usage: /thread child <title> (requires active thread)"))]
             ["info"
              (define current (local-thread-get-active))
              (if current
                  (let* ([thread (local-thread-find current)]
                         [rels (if thread (local-thread-get-relations current) '())]
                         [contexts (if thread (local-context-list current) '())])
                    (if thread
                        (begin
                          (printf "\nThread: ~a\n" (hash-ref thread 'id))
                          (printf "Title: ~a\n" (or (hash-ref thread 'title) "Untitled"))
                          (printf "Status: ~a\n" (hash-ref thread 'status))
                          (printf "Created: ~a\n" (date->string (seconds->date (hash-ref thread 'created_at)) #t))
                          (when (hash-ref thread 'summary #f)
                            (printf "Summary: ~a\n" (hash-ref thread 'summary)))
                          (unless (null? rels)
                            (printf "\nRelations:\n")
                            (for ([r rels])
                              (printf "  ~a -> ~a (~a)\n" 
                                      (hash-ref r 'from) 
                                      (hash-ref r 'to) 
                                      (hash-ref r 'type))))
                          (unless (null? contexts)
                            (printf "\nContext Nodes:\n")
                            (for ([c contexts])
                              (printf "  [~a] ~a\n" (hash-ref c 'kind) (hash-ref c 'title)))))
                        (displayln "Thread not found.")))
                  (displayln "No active thread."))]
             ["context"
              (define current (local-thread-get-active))
              (if (and current (>= (length parts) 2))
                  (let* ([sub-cmd (second parts)]
                         [rest-parts (if (>= (length parts) 3) (cddr parts) '())])
                    (match sub-cmd
                      ["add"
                       (if (>= (length rest-parts) 1)
                           (let* ([title (string-join rest-parts " ")]
                                  [id (local-context-create! current title)])
                             (printf "Created context node: ~a\n" id))
                           (displayln "Usage: /thread context add <title>"))]
                      ["list"
                       (let ([contexts (local-context-list current)])
                         (if (null? contexts)
                             (displayln "No context nodes.")
                             (for ([c contexts])
                               (printf "  [~a] ~a: ~a\n" 
                                       (hash-ref c 'kind) 
                                       (hash-ref c 'id)
                                       (hash-ref c 'title)))))]
                      [_ (displayln "Usage: /thread context <add|list> ...")]))
                  (displayln "Usage: /thread context <add|list> ... (requires active thread)"))]
             [_ (displayln "Unknown thread command. Try: list, new, switch, continue, child, info, context")])
           (displayln "Usage: /thread <list|new|switch|continue|child|info|context> ..."))]

      [(or "attach" "file")
       (define start-idx (if (string-prefix? input "/attach") 8 6))
       (define path (if (>= (string-length input) start-idx)
                        (string-trim (substring input start-idx))
                        ""))
       (if (file-exists? path)
           (begin
             (attachments (cons (list 'file path (file->string path)) (attachments)))
             (printf "Attached file: ~a\n" path))
           (printf "File not found: ~a\n" path))]
      ["image"
       (define path (if (>= (string-length input) 7)
                        (string-trim (substring input 7))
                        ""))
       (begin
         (attachments (cons (list 'image path) (attachments)))
         (printf "Attached image: ~a\n" path))]
      ["models"
       (define rest (if (>= (string-length input) 8)
                        (string-trim (substring input 8))
                        ""))
       (with-handlers ([exn:fail?
                        (λ (e)
                          (eprintf "[ERROR] Failed to fetch models: ~a\n" (exn-message e))
                          (eprintf "Check your API endpoint and key configuration.\n"))])
         (cond
           [(string=? rest "")
            ;; No query - list all models
            (printf "Fetching available models from ~a...\n" (base-url-param))
            (define models
              (if fetch-models
                  (fetch-models (base-url-param) api-key)
                  (fetch-models-from-endpoint (base-url-param) api-key)))
            (if (null? models)
                (printf "No models found. The API endpoint may not support model listing.\n")
                (begin
                  (printf "\nAvailable Models:\n")
                  (for ([m models])
                    (define model-id
                      (cond
                        [(hash? m) (hash-ref m 'id (hash-ref m 'name "unknown"))]
                        [(string? m) m]
                        [else "unknown"]))
                    (printf "  - ~a\n" model-id))
                  (printf "\nUse '/models <query>' to search models.\n")
                  (printf "Use '/config model <name>' to set a model.\n")))]
           [else
             ;; With query - fuzzy search
             ;; First, ensure model registry is initialized with models from the endpoint
             (printf "Searching models for: ~a\n" rest)
             (define available-models (list-available-models))
             (when (null? available-models)
               (printf "Initializing model registry...\n")
               (with-handlers ([exn:fail? (λ (e) 
                                            (log-debug 1 'models "Failed to init registry: ~a" (exn-message e)))])
                 (define fetched (fetch-models-from-endpoint (base-url-param) api-key))
                 (for ([m (in-list fetched)])
                   (define model-id (cond
                                     [(hash? m) (hash-ref m 'id (hash-ref m 'name "unknown"))]
                                     [(string? m) m]
                                     [else #f]))
                   (when model-id
                     (register-model! model-id)))))
             (define results (fuzzy-search-models rest))
             (if (null? results)
                 (printf "No matching models found. Try '/models' to list all available models first.\n")
                 (begin
                   (printf "\nMatching Models:\n")
                   (for ([result (in-list results)])
                     (define score (car result))
                     (define caps (cdr result))
                     (define id (ModelCapabilities-id caps))
                     (printf "  - ~a" id)
                     (when (> score 0)
                       (printf " (relevance: ~a)" score))
                     (newline))
                   (printf "\nUse '/config model <name>' to set a model.\n")))]))
           ]

      ["workflows"
       (define rest (if (>= (string-length input) 10)
                        (string-trim (substring input 10))
                        ""))
       (define parts (if (> (string-length rest) 0)
                         (string-split rest)
                         '()))
       (cond
         [(or (null? parts) (equal? (first parts) "list"))
          (with-handlers ([exn:fail? (λ (e)
                                       (eprintf "[ERROR] Failed to list workflows: ~a\n" (exn-message e)))])
            (define workflows-json (workflow-list))
            (define workflows (string->jsexpr workflows-json))
            (if (null? workflows)
                (printf "No workflows found. Use workflow tools to create workflows.\n")
                (begin
                  (printf "\nAvailable Workflows:\n")
                  (for ([w workflows])
                    (define slug (hash-ref w 'slug "unknown"))
                    (define desc (hash-ref w 'description "No description"))
                    (printf "  ~a - ~a\n" slug desc))
                  (printf "\nUse '/workflows show <slug>' to view a workflow.\n"))))]
         [(and (>= (length parts) 2) (equal? (first parts) "show"))
          (define slug (second parts))
          (with-handlers ([exn:fail? (λ (e)
                                       (eprintf "[ERROR] Failed to get workflow: ~a\n" (exn-message e)))])
            (define content (workflow-get slug))
            (if (equal? content "null")
                (printf "Workflow '~a' not found.\n" slug)
                (begin
                  (printf "\nWorkflow: ~a\n" slug)
                  (printf "Content:\n~a\n" content))))]
         [(and (>= (length parts) 2) (equal? (first parts) "delete"))
          (define slug (second parts))
          (with-handlers ([exn:fail? (λ (e)
                                       (eprintf "[ERROR] Failed to delete workflow: ~a\n" (exn-message e)))])
            (define result (workflow-delete slug))
            (printf "~a\n" result))]
         [else
          (displayln "Usage: /workflows [list|show <slug>|delete <slug>]")])]

      ["lsp"
       (define rest (if (>= (string-length input) 4)
                        (string-trim (substring input 4))
                        ""))
       (define parts (if (> (string-length rest) 0)
                         (string-split rest)
                         '()))
       (cond
         [(or (null? parts) (equal? (first parts) "list"))
          (define servers (lsp-list-servers))
          (if (null? servers)
              (displayln "No LSP servers running.")
              (begin
                (displayln "Running LSP servers:")
                (for ([s servers])
                  (define lang (hash-ref s 'language))
                  (define status (lsp-status))
                  (define proc-status (hash-ref status lang))
                  (printf "  - ~a: ~a\n" lang proc-status))))]
         [(and (>= (length parts) 2) (equal? (first parts) "start"))
          (define lang (second parts))
          (define root-path (if (>= (length parts) 3) (third parts) (current-directory)))
          (with-handlers ([exn:fail? (λ (e) (eprintf "Failed to start LSP: ~a\n" (exn-message e)))])
            (printf "~a\n" (lsp-start! lang #:root-path root-path)))]
         [(and (>= (length parts) 2) (equal? (first parts) "stop"))
          (define lang (second parts))
          (with-handlers ([exn:fail? (λ (e) (eprintf "Failed to stop LSP: ~a\n" (exn-message e)))])
            (printf "~a\n" (lsp-stop! lang)))]
         [(equal? (first parts) "status")
          (define status (lsp-status))
          (if (hash-empty? status)
              (displayln "No LSP servers running.")
              (begin
                (displayln "LSP server status:")
                (for ([(lang st) (in-hash status)])
                  (printf "  ~a: ~a\n" lang st))))]
         [else
          (displayln "Usage: /lsp [list|start <lang>|stop <lang>|status]")])]

      ["undo"
       (define rest (if (>= (string-length input) 5)
                        (string-trim (substring input 5))
                        ""))
       (if (string=? rest "")
           (displayln "Usage: /undo <path> [steps]\n  Example: /undo /path/to/file.rkt\n  Example: /undo /path/to/file.rkt 2")
           (let* ([parts (string-split rest)]
                  [path (first parts)]
                  [steps (if (>= (length parts) 2) (string->number (second parts)) 1)])
             (define-values (success? msg) (file-rollback! path (or steps 1)))
             (if success?
                 (printf "✓ ~a\n" msg)
                 (printf "✗ ~a\n" msg))))]
      
      ["rollbacks"
       (define rest (if (>= (string-length input) 10)
                        (string-trim (substring input 10))
                        ""))
       (if (string=? rest "")
           (let ([stats (rollback-history-size)])
             (printf "Rollback History: ~a files, ~a bytes\n" 
                     (hash-ref stats 'files)
                     (hash-ref stats 'bytes)))
           (let ([history (file-rollback-list rest)])
             (if (null? history)
                 (displayln "No rollback history for this file.")
                 (begin
                   (printf "Rollback history for ~a:\n" rest)
                   (for ([h (in-list history)])
                     (printf "  ~a. ~a (~a bytes)\n" 
                             (hash-ref h 'step)
                             (hash-ref h 'date)
                             (hash-ref h 'size)))))))]
      
      ["stats"
       (display (session-stats-display))]
      
      ["context"
       (display (session-stats-display #:compact? #f))]
      
      ["init"
       (printf "Initializing agent for project...\n")
       (define init-prompt #<<EOF
Analyze this codebase and create/update **agents.md** to help future agents work effectively in this repository.

**First**: Check if directory is empty or only contains config files. If so, stop and say "Directory appears empty or only contains config. Add source code first, then run this command to generate agents.md."

**Goal**: Document what an agent needs to know to work in this codebase - commands, patterns, conventions, gotchas.

**Discovery process**:

1. Check directory contents with `ls`
2. Look for existing rule files (`.cursor/rules/*.md`, `.cursorrules`, `.github/copilot-instructions.md`, `claude.md`, `agents.md`) - only read if they exist
3. Identify project type from config files and directory structure
4. Find build/test/lint commands from config files, scripts, Makefiles, or CI configs
5. Read representative source files to understand code patterns
6. If agents.md exists, read and improve it

**Content to include**:

- Essential commands (build, test, run, deploy, etc.) - whatever is relevant for this project
- Code organization and structure
- Naming conventions and style patterns
- Testing approach and patterns
- Important gotchas or non-obvious patterns
- Any project-specific context from existing rule files

**Format**: Clear markdown sections. Use your judgment on structure based on what you find. Aim for completeness over brevity - include everything an agent would need to know.

**Critical**: Only document what you actually observe. Never invent commands, patterns, or conventions. If you can't find something, don't include it.
EOF
         )
       (when run-turn
         (run-turn "cli" init-prompt (λ (s) (display s) (flush-output)) (λ (_) (void)) (λ () #f)))]

       ["history"
       (define rest (if (>= (string-length input) 8)
                       (string-trim (substring input 8))
                       ""))
       (define hist (command-history))
       (cond
        [(string=? rest "")
         (if (null? hist)
             (displayln "No command history.")
             (begin
               (displayln "\nCommand History (most recent first):")
               (for ([cmd (in-list hist)]
                     [i (in-naturals 1)])
                 (printf "  ~a. ~a~n" i cmd))
               (displayln "\nUse '/history <n>' to re-run command n.")))]
        [else
         (define n (string->number rest))
         (if (and n (> n 0) (<= n (length hist)))
             (let ([cmd-to-run (list-ref hist (sub1 n))])
               (printf "Re-running: ~a~n" cmd-to-run)
               (when run-turn
                 (run-turn "cli" cmd-to-run (λ (s) (display s) (flush-output)) (λ (_) (void)) (λ () #f))))
             (printf "Invalid history index. Use 1 to ~a.~n" (length hist)))])]

       ["queue"
       (define rest (if (>= (string-length input) 6)
                       (string-trim (substring input 6))
                       ""))
       (define parts (if (> (string-length rest) 0)
                        (string-split rest #:trim? #f)
                        '()))
       (cond
        [(null? parts)
         (define q (list-queue))
         (if (null? q)
             (displayln "Queue is empty. Use '/queue <task>' to add tasks.")
             (begin
               (displayln "\nQueued Tasks:")
               (for ([task (in-list q)]
                     [i (in-naturals 1)])
                 (printf "  ~a. ~a~n" i task))
               (displayln "\nTasks will be processed in order after current work completes.")))]
        [(equal? (first parts) "clear")
         (clear-queue!)
         (displayln "Queue cleared.")]
        [(equal? (first parts) "pop")
         (define task (get-next-queued!))
         (if task
             (printf "Removed from queue: ~a~n" task)
             (displayln "Queue is empty."))]
        [(and (equal? (first parts) "remove") (= (length parts) 2))
         (define n (string->number (second parts)))
         (if (and n (remove-queue-item! (sub1 n)))
             (printf "Removed item ~a from queue.~n" n)
             (displayln "Invalid queue index."))]
        [else
         (define task (string-join parts " "))
         (if (add-to-queue! task)
             (printf "Added to queue (~a pending): ~a~n" (queue-length) task)
             (displayln "Queue is full (max 20). Use '/queue pop' or '/queue clear'."))])]
       
       [_
       (define candidates '("exit" "quit" "help" "raco" "config" "models" "workflows" "init" "lsp" "history" "queue"))
       (define suggestions (filter (λ (c) (<= (levenshtein cmd c) 2)) candidates))
       (if (not (null? suggestions))
           (printf "Unknown command '/~a'. Did you mean: /~a?\n" cmd (string-join suggestions ", /"))
           (printf "Unknown command '/~a'. Type /help for list.\n" cmd))])))
