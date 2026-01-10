#lang racket
(require racket/cmdline json racket/file racket/list "dotenv.rkt"
         "dspy-core.rkt" "openai-responses-stream.rkt" "context-store.rkt" "openai-client.rkt"
         "acp-tools.rkt" "acp-stdio.rkt" "optimizer-gepa.rkt" "trace-store.rkt"
         "rdf-tools.rkt" "process-supervisor.rkt" "sandbox-exec.rkt"
         "rdf-tools.rkt" "process-supervisor.rkt" "sandbox-exec.rkt" "debug.rkt"
         "pricing-model.rkt" "vector-store.rkt" "workflow-engine.rkt" "utils-time.rkt"
         "web-search.rkt")

(load-dotenv!)
(define api-key (getenv "OPENAI_API_KEY"))
(define env-api-key api-key)
(define base-url-param (make-parameter (or (getenv "OPENAI_API_BASE") "https://api.openai.com/v1")))
(define model-param (make-parameter "gpt-5.2"))
(define vision-model-param (make-parameter "gpt-5.2"))
(define interactive-param (make-parameter #f))
(define attachments (make-parameter '())) ; List of (type content) pairs

(define budget-param (make-parameter +inf.0))
(define timeout-param (make-parameter +inf.0))
(define pretty-param (make-parameter "none"))
(define session-start-time (current-seconds))
(define total-session-cost 0.0)

(define current-security-level (make-parameter 1))

(define ACP-MODES
  (list (hash 'slug "ask" 'name "Ask" 'description "Read only.")
        (hash 'slug "architect" 'name "Architect" 'description "Read files.")
        (hash 'slug "code" 'name "Code" 'description "Full FS/Net.")
        (hash 'slug "semantic" 'name "Semantic" 'description "RDF Graph.")))

(define (confirm-risk! action description)
  (printf "\n[ALERT] ~a: ~a. Allow? [y/N]: " action description)
  (flush-output)
  (if (member (string-downcase (or (read-line) "n")) '("y" "yes")) #t (error 'security "Denied.")))

(define (execute-tool name args)
  (with-handlers ([exn:fail? (λ (e) (format "Tool Error: ~a" (exn-message e)))])
    (cond
    [(string-prefix? name "rdf_") (execute-rdf-tool name args)]
    [(string-prefix? name "web_") (execute-web-search name args)]
    [(string-prefix? name "service_") (if (>= (current-security-level) 2) 
                                          (match name ["service_start" (spawn-service! (hash-ref args 'id) (hash-ref args 'cmd) api-key)] 
                                                 ["service_stop" (stop-service! (hash-ref args 'id))] ["service_list" (list-services!)])
                                          "Requires Level 2.")]
    [else (match name
            ["ask_human" (printf "\n[ASK]: ~a\n> " (hash-ref args 'question)) (read-line)]
            ["ctx_evolve" (gepa-evolve! (hash-ref args 'feedback) (hash-ref args 'model "gpt-5.2"))]
            ["meta_evolve" (gepa-meta-evolve! (hash-ref args 'feedback) (hash-ref args 'model "gpt-5.2"))]
            ["run_racket" (run-tiered-code! (hash-ref args 'code) (current-security-level))]
            ["read_file" (if (or (>= (current-security-level) 1) (string-contains? (hash-ref args 'path) ".agentd/workspace")) 
                             (if (file-exists? (hash-ref args 'path)) (file->string (hash-ref args 'path)) "404") "Permission Denied.")]
            ["write_file" (if (>= (current-security-level) 2) 
                              (begin (confirm-risk! "WRITE" (hash-ref args 'path)) (display-to-file (hash-ref args 'content) (hash-ref args 'path) #:exists 'replace) "Written.")
                              "Permission Denied: Requires Level 2.")]
            ["run_term" (if (= (current-security-level) 3) 
                            (begin (confirm-risk! "TERM" (hash-ref args 'cmd)) (with-output-to-string (λ () (system (hash-ref args 'cmd)))))
                            "Permission Denied: Requires Level 3.")]
            ["memory_save"
             (vector-add! (hash-ref args 'text) api-key (base-url-param))
             "Saved to vector memory."]
             ["memory_recall"
              (define results (vector-search (hash-ref args 'query) api-key (base-url-param)))
              (format "Related memories:\n~a" 
                      (string-join (map (λ (x) (format "- [~a] ~a" (real->decimal-string (car x) 2) (cdr x))) results) "\n"))]
             ["workflow_list" (workflow-list)]
             ["workflow_set" (workflow-set (hash-ref args 'slug) (hash-ref args 'description) (hash-ref args 'content))]
             ["workflow_delete" (workflow-delete (hash-ref args 'slug))]
             ["generate_image"
              (define gen (make-openai-image-generator #:api-key api-key #:api-base (base-url-param)))
              (define-values (ok? url) (gen (hash-ref args 'prompt)))
              (if ok? (format "Generated Image: ~a" url) (format "Failed: ~a" url))]
            [_ (format "Unknown: ~a" name)]
             )])))

(define (get-tools mode)
  (define mem-tools (list (hash 'type "function" 'function (hash 'name "memory_save" 'parameters (hash 'type "object" 'properties (hash 'text (hash 'type "string")))))
                          (hash 'type "function" 'function (hash 'name "memory_recall" 'parameters (hash 'type "object" 'properties (hash 'query (hash 'type "string")))))))
  
  (define base (list (hash 'type "function" 'function (hash 'name "ask_human" 'parameters (hash 'type "object" 'properties (hash 'question (hash 'type "string")))))
                     (hash 'type "function" 'function (hash 'name "ctx_evolve" 'parameters (hash 'type "object" 'properties (hash 'feedback (hash 'type "string") 'model (hash 'type "string")))))
                     (hash 'type "function" 'function (hash 'name "meta_evolve" 'parameters (hash 'type "object" 'properties (hash 'feedback (hash 'type "string") 'model (hash 'type "string")))))
                     (hash 'type "function" 'function (hash 'name "run_racket" 'parameters (hash 'type "object" 'properties (hash 'code (hash 'type "string")))))
                     (hash 'type "function" 'function (hash 'name "workflow_list" 'parameters (hash 'type "object" 'properties (hash))))
                     (hash 'type "function" 'function (hash 'name "workflow_get" 'parameters (hash 'type "object" 'properties (hash 'slug (hash 'type "string")))))
                     (hash 'type "function" 'function (hash 'name "workflow_set" 'parameters (hash 'type "object" 'properties (hash 'slug (hash 'type "string") 'description (hash 'type "string") 'content (hash 'type "string")))))
                     (hash 'type "function" 'function (hash 'name "workflow_delete" 'parameters (hash 'type "object" 'properties (hash 'slug (hash 'type "string")))))
                     (hash 'type "function" 'function (hash 'name "generate_image" 'parameters (hash 'type "object" 'properties (hash 'prompt (hash 'type "string")))))))
  (define fs (make-acp-tools))
  (define term (list (hash 'type "function" 'function (hash 'name "run_term" 'parameters (hash 'type "object" 'properties (hash 'cmd (hash 'type "string")))))))
  (define tools (match mode
    ['ask base]
    ['architect (append base (list (first fs)))] ; read only
    ['code (append base fs term (get-supervisor-tools) (make-rdf-tools) (make-web-search-tools) mem-tools)]
    ['semantic (append base (make-rdf-tools) mem-tools)]
    [_ base]))
  (log-debug 1 'tools "Available tools: ~a" (map (λ (t) (hash-ref (hash-ref t 'function) 'name)) tools))
  tools)
(define CONTEXT-LIMIT-TOKENS (make-parameter 100000)) ;; Configurable context limit

(define (acp-run-turn sid prompt-blocks emit! tool-emit! cancelled?)
  (define ctx (ctx-get-active))
  (define input-content 
    (cond
      [(string? prompt-blocks)
       (if (null? (attachments))
           prompt-blocks
           (append (list (hash 'type "text" 'text prompt-blocks))
                   (for/list ([a (attachments)])
                     (match a
                       [(list 'image path) (hash 'type "image_url" 'image_url (hash 'url (if (string-prefix? path "http") path (format "data:image/jpeg;base64,~a" path))))]
                       [(list 'file path content) (hash 'type "text" 'text (format "Attached File (~a):\n```\n~a\n```" path content))]))))]
      [else (hash-ref (first prompt-blocks) 'text)]))
      
  ;; Build history with compacted summary if it exists
  (define base-history
    (if (null? (Ctx-history ctx))
        ;; Fresh start - include compacted summary if available
        (if (> (string-length (Ctx-compacted-summary ctx)) 0)
            (list (hash 'role "system" 'content (Ctx-system ctx))
                  (hash 'role "system" 'content (format "Previous conversation summary:\n~a" (Ctx-compacted-summary ctx))))
            (list (hash 'role "system" 'content (Ctx-system ctx))))
        (Ctx-history ctx)))
  
  (define history (append base-history (list (hash 'role "user" 'content input-content))))

  
  ;; Auto-switch to vision model if images are present
  (define has-images? (and (list? input-content) (ormap (λ (x) (equal? (hash-ref x 'type) "image_url")) input-content)))
  (define current-model (if has-images? (vision-model-param) (model-param)))
  
  (let loop ([msgs history])
    ;; Clear attachments after they are consumed in the first turn
    (attachments '())
    ;; Budget & Timeout Checks
    (define elapsed (- (current-seconds) session-start-time))
    (define remaining-time (- (timeout-param) elapsed))
    (define remaining-budget (- (budget-param) total-session-cost))

    (when (or (<= remaining-time 0) (<= remaining-budget 0))
      (error 'resource-limit "Resource Limit Exceeded: Execution stopped."))
    
    (define effective-msgs 
      (if (or (< remaining-time 30) (< remaining-budget 0.01))
          (append msgs (list (hash 'role "system" 'content "CRITICAL: Resource limit approaching. Stop all tool usage. Summarize your work and answer the user immediately.")))
          msgs))

    (define (mk-req) (hash 'model current-model 'messages effective-msgs 'tools (get-tools (Ctx-mode ctx)) 'stream #t))
    (define-values (assistant-msg res usage) 
      (responses-run-turn/stream #:api-key api-key #:make-request mk-req #:emit! emit! #:tool-run execute-tool #:cancelled? cancelled? #:api-base (base-url-param)))
    
    (define in-tok (hash-ref usage 'prompt_tokens 0))
    (define out-tok (hash-ref usage 'completion_tokens 0))
    (define cost (calculate-cost current-model in-tok out-tok))
    (set! total-session-cost (+ total-session-cost cost))

    (if (null? res)
      ;; Final turn: Save history back to context, with compaction if needed
      (let* ([db (load-ctx)]
             [items (hash-ref db 'items)]
             [active-id (hash-ref db 'active)]
             [current-ctx (hash-ref items active-id)]
             [final-msgs (append msgs (list assistant-msg))]
             ;; Check if we need to compact
             [estimated-tokens (estimate-tokens (jsexpr->string final-msgs))]
             [compact-threshold (* 0.8 (CONTEXT-LIMIT-TOKENS))])
        (if (> estimated-tokens compact-threshold)
            ;; Compact: summarize first half of messages, keep recent ones
            (let* ([mid (quotient (length final-msgs) 2)]
                   [msgs-to-compact (take final-msgs mid)]
                   [msgs-to-keep (drop final-msgs mid)]
                   [old-summary (Ctx-compacted-summary current-ctx)]
                   [new-summary (summarize-conversation msgs-to-compact 
                                                        #:model (model-param) 
                                                        #:api-key api-key 
                                                        #:api-base (base-url-param))]
                   [combined-summary (if (> (string-length old-summary) 0)
                                         (format "~a\n\n---\n\n~a" old-summary new-summary)
                                         new-summary)])
              (save-ctx! (hash-set db 'items 
                           (hash-set items active-id 
                             (struct-copy Ctx current-ctx 
                               [history msgs-to-keep]
                               [compacted-summary combined-summary])))))
            ;; No compaction needed
            (save-ctx! (hash-set db 'items (hash-set items active-id (struct-copy Ctx current-ctx [history final-msgs]))))))
      (begin
        (log-trace! #:task "Turn" #:history msgs #:tool-results res #:final-response "Streamed" #:tokens usage #:cost cost)
        (loop (append msgs (list assistant-msg) res))))))

(define (handle-new-session sid mode) 
  (save-ctx! (let ([db (load-ctx)]) (hash-set db 'items (hash-set (hash-ref db 'items) (hash-ref db 'active) (struct-copy Ctx (ctx-get-active) [mode (string->symbol mode)]))))))


(require racket/system)

(define (levenshtein s1 s2)
  (let* ([len1 (string-length s1)]
         [len2 (string-length s2)]
         [matrix (make-vector (add1 len1))])
    (for ([i (in-range (add1 len1))])
      (vector-set! matrix i (make-vector (add1 len2))))
    (for ([i (in-range (add1 len1))])
      (vector-set! (vector-ref matrix i) 0 i))
    (for ([j (in-range (add1 len2))])
      (vector-set! (vector-ref matrix 0) j j))
    (for ([i (in-range 1 (add1 len1))])
      (for ([j (in-range 1 (add1 len2))])
        (let ([cost (if (char=? (string-ref s1 (sub1 i)) (string-ref s2 (sub1 j))) 0 1)])
          (vector-set! (vector-ref matrix i) j
                       (min (add1 (vector-ref (vector-ref matrix (sub1 i)) j))
                            (add1 (vector-ref (vector-ref matrix i) (sub1 j)))
                            (+ cost (vector-ref (vector-ref matrix (sub1 i)) (sub1 j))))))))
    (vector-ref (vector-ref matrix len1) len2)))

(define (verify-env! #:fail [fail? #f])
  (unless env-api-key
    (if fail?
        (begin (eprintf "[ERROR] OPENAI_API_KEY not found.\n") (exit 1))
        (begin (displayln "[WARNING] OPENAI_API_KEY not found.") (displayln "Usage: export OPENAI_API_KEY=sk-..."))))
  
  (when env-api-key
    (define-values (ok? msg) (validate-api-key env-api-key (base-url-param)))
    (unless ok?
      (if fail?
          (begin (eprintf "[ERROR] API Key Validation Failed: ~a\n" msg) (exit 1))
          (printf "[WARNING] API Key Validation Failed: ~a\n" msg)))))

(define (handle-slash-command cmd input)
  (match cmd
    [(or "exit" "quit") (displayln "Goodbye.") (exit)]
    ["help" (displayln "Commands:\n  /help - Show this message\n  /exit, /quit - Exit\n  /raco <args> - Run raco commands\n  /config <key> <val> - Set param\n  /init - Initialize project")]
    ["raco" (system (format "raco ~a" (substring input 6)))]
    ["config" 
     (define parts (string-split (substring input 8)))
     (if (= (length parts) 2)
         (match (first parts)
           ["model" (model-param (second parts)) (printf "Model set to ~a\n" (second parts))]
           ["budget" (budget-param (string->number (second parts))) (printf "Budget set to ~a\n" (second parts))]
           [_ (printf "Unknown config key: ~a\n" (first parts))])
         (displayln "Usage: /config <key> <value>"))]

    ["session"
     (define parts (string-split (string-trim (substring input 8))))
     (if (>= (length parts) 1)
         (match (first parts)
           ["list" 
            (define-values (sessions active) (session-list))
            (printf "Sessions:\n")
            (for ([s sessions])
              (printf "  ~a~a\n" (if (equal? s active) "* " "- ") s))]
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

    [(or "attach" "file")
     (define path (string-trim (substring input (if (string-prefix? input "/attach") 8 6))))
     (if (file-exists? path)
         (begin
           (attachments (cons (list 'file path (file->string path)) (attachments)))
           (printf "Attached file: ~a\n" path))
         (printf "File not found: ~a\n" path))]
    ["image"
     (define path (string-trim (substring input 7)))
     (begin
       ;; In a real app we'd base64 encode here, for now assuming path or URL
       ;; For local files, we'd need to implementing base64 reading.
       (attachments (cons (list 'image path) (attachments)))
       (printf "Attached image: ~a\n" path))]
    ["init"
     (printf "Initializing agent for project...\n")
     (define init-prompt (format #<<EOF
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
))
     (acp-run-turn "cli" init-prompt (λ (s) (display s) (flush-output)) (λ (_) (void)) (λ () #f))]
    [_ 
     (define candidates '("exit" "quit" "help" "raco" "config" "init"))
     (define suggestions (filter (λ (c) (<= (levenshtein cmd c) 2)) candidates))
     (if (not (null? suggestions))
         (printf "Unknown command '/~a'. Did you mean: /~a?\n" cmd (string-join suggestions ", /"))
         (printf "Unknown command '/~a'. Type /help for list.\n" cmd))]))

(define (repl-loop)
  (verify-env! #:fail #f)
  (displayln "Welcome to Chrysalis Forge Interactive Mode.")
  (displayln "Type /exit to leave or /help for commands.")
  (handle-new-session "cli" "code")
  (let loop ()
    (display "\n[USER]> ")(flush-output)
    (define input (read-line))
    (when (and input (not (eof-object? input)))
      (cond
        [(string-prefix? input "/")
         (define cmd (first (string-split (substring input 1))))
         (handle-slash-command cmd input)]
        [else
         (acp-run-turn "cli" input (λ (s) (display s) (flush-output)) (λ (_) (void)) (λ () #f))])
      (loop))))

(define mode-param (make-parameter 'run))
(command-line #:program "agentd" 
              #:once-each 
              [("--acp") "Run ACP" (mode-param 'acp)]
              [("--perms") p "Security Level (0, 1, 2, god)"
                           (match p
                             ["0" (current-security-level 0)]
                             ["1" (current-security-level 1)]
                             ["2" (current-security-level 2)]
                             ["god" (current-security-level 3)]
                             [_ (error "Invalid permission level. Use 0, 1, 2, or god.")])]

              [("--base-url") url "Override OpenAI API Base URL" (base-url-param url)]
              [("--model") m "Override Default Model" (model-param m)]
              [("--budget") b "Set Session Budget (USD)" (budget-param (string->number b))]
              [("--timeout") t "Set Session Timeout (e.g. 10s, 5m)" (timeout-param (parse-duration t))]
              [("--pretty") p "Output format (e.g. glow)" (pretty-param p)]
              [("-d" "--debug") "Enable Debug Mode (Level 1)" (current-debug-level 1)]
              [("-v" "--verbose") "Enable Verbose Debug Mode (Level 2)" (current-debug-level 2)]
              [("-i" "--interactive") "Enter Interactive Mode" (interactive-param #t)]
              #:args raw-args
              (match (mode-param)
                ['run (begin
                        (set! session-start-time (current-seconds)) ;; Reset start time for run
                        (if (or (interactive-param) (null? raw-args))
                          (repl-loop)
                          (begin
                             (verify-env! #:fail #t)
                             (let ([task (string-join raw-args " ")])
                               (handle-new-session "cli" "code") 
                               (cond
                                 [(equal? (pretty-param) "glow")
                                  ;; Pipe to glow
                                  (define-values (sp stdout stdin stderr) 
                                    (subprocess (current-output-port) #f (current-error-port) (find-executable-path "glow") "-"))
                                  (acp-run-turn "cli" task (λ (s) (display s stdin) (flush-output stdin)) (λ (_) (void)) (λ () #f))
                                  (close-output-port stdin)
                                  (subprocess-wait sp)]
                                 [else
                                  (acp-run-turn "cli" task (λ (s) (display s) (flush-output)) (λ (_) (void)) (λ () #f))])))))]
                ['acp (acp-serve #:modes ACP-MODES #:on-new-session handle-new-session #:run-turn acp-run-turn)]))