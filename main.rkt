#lang racket
(require racket/cmdline json racket/file racket/list racket/format racket/date racket/string racket/match racket/system
         "src/core/acp-stdio.rkt" "src/stores/context-store.rkt" "src/llm/dspy-core.rkt"
         "src/utils/dotenv.rkt" "src/llm/openai-responses-stream.rkt" "src/llm/openai-client.rkt"
         "src/tools/acp-tools.rkt" "src/core/optimizer-gepa.rkt" "src/stores/trace-store.rkt" "src/tools/rdf-tools.rkt"
         "src/core/process-supervisor.rkt" "src/tools/sandbox-exec.rkt" "src/utils/debug.rkt" "src/llm/pricing-model.rkt"
         "src/stores/vector-store.rkt" "src/core/workflow-engine.rkt" "src/utils/utils-time.rkt" "src/tools/web-search.rkt"
         "src/stores/eval-store.rkt" "src/tools/mcp-client.rkt" "src/llm/model-registry.rkt"
         "src/stores/thread-store.rkt" "src/stores/rollback-store.rkt" "src/stores/session-stats.rkt" "src/tools/lsp-client.rkt"
         "src/utils/terminal-style.rkt"
         "src/utils/message-boxes.rkt"
         "src/utils/status-bar.rkt"
         "src/utils/session-summary-viz.rkt"
         "src/utils/tool-visualization.rkt"
         ;; Modular imports - runtime state, commands, and REPL
         "src/core/runtime.rkt"
         "src/core/commands.rkt"
         "src/core/repl.rkt")

;; Conditionally require service module (may not exist yet)
(define service-available?
  (with-handlers ([exn:fail? (λ (_) #f)])
    (dynamic-require 'chrysalis-forge/src/service/service-server 'start-service!)
    #t))

(define (start-service! . args)
  (if service-available?
      (apply (dynamic-require 'chrysalis-forge/src/service/service-server 'start-service!) args)
      (begin
        (eprintf "[ERROR] Service module not available. Run 'raco pkg install' first.~n")
        (exit 1))))

(define (run-daemon!)
  (if service-available?
      ((dynamic-require 'chrysalis-forge/src/service/service-server 'run-daemon!))
      (begin
        (eprintf "[ERROR] Service module not available. Run 'raco pkg install' first.~n")
        (exit 1))))

;; Client mode support
(define client-available?
  (with-handlers ([exn:fail? (λ (_) #f)])
    (dynamic-require 'chrysalis-forge/src/service/client 'client-repl)
    #t))

(define (client-repl url #:api-key [api-key #f])
  (if client-available?
      ((dynamic-require 'chrysalis-forge/src/service/client 'client-repl) url #:api-key api-key)
      (begin
        (eprintf "[ERROR] Client module not available.~n")
        (exit 1))))

(load-dotenv!)

;; Helper to get default model from config/env/.env, with fallback
;; Priority: 1) MODEL env var (explicit override), 2) Config system (CHRYSALIS_DEFAULT_MODEL env or config file), 3) Hardcoded default
(define (get-default-model)
  (or (getenv "MODEL")
      (and service-available?
           (with-handlers ([exn:fail? (λ (_) #f)])
             ((dynamic-require 'chrysalis-forge/src/service/config 'config-default-model))))
      (getenv "CHRYSALIS_DEFAULT_MODEL")
      "gpt-5.2"))

;; Override model-param with config-aware default (runtime.rkt provides the base)
(model-param (get-default-model))
(vision-model-param (or (getenv "VISION_MODEL") (get-default-model)))

;; ACP/Service mode parameters (not in runtime.rkt)
(define acp-port-param (make-parameter (or (getenv "ACP_PORT") "stdio")))

;; Service mode parameters
(define serve-port-param (make-parameter (or (getenv "CHRYSALIS_PORT") 8080)))
(define serve-host-param (make-parameter (or (getenv "CHRYSALIS_HOST") "127.0.0.1")))
(define daemon-param (make-parameter #f))
(define config-path-param (make-parameter #f))

;; Client mode parameters
(define client-url-param (make-parameter "http://127.0.0.1:8080"))
(define client-api-key-param (make-parameter #f))

;; Session management parameters
(define session-action-param (make-parameter #f)) ; #f = new session, "resume" = resume last, string = resume by ID, "list" = list sessions

(define ACP-MODES
  (list (hash 'id "ask" 'name "Ask" 'description "Read only.")
        (hash 'id "architect" 'name "Architect" 'description "Read files.")
        (hash 'id "code" 'name "Code" 'description "Full FS/Net.")
        (hash 'id "semantic" 'name "Semantic" 'description "RDF Graph.")))

(define (confirm-risk! action description)
  (printf "\n[ALERT] ~a: ~a. Allow? [y/N]: " action description)
  (flush-output)
  (if (member (string-downcase (or (read-line) "n")) '("y" "yes")) #t (error 'security "Denied.")))

(define (evaluate-safety action content)
  (unless (llm-judge-param) (values #t "")) ;; Pass if judge not enabled

  (define sender (make-openai-sender #:model (llm-judge-model-param)))
  (define prompt (format "You are a Security Auditor. A user or agent is attempting the following action:\nACTION: ~a\nCONTENT/COMMAND:\n~a\n\nIs this action safe and appropriate? If YES, reply with handling details and end with [SAFE]. If NO, explain why and end with [UNSAFE]." action content))
  (define-values (ok? res usage) (sender prompt))
  (if (and ok? (string-contains? res "[SAFE]"))
      (values #t res)
      (values #f res)))

(define (record-tool-call! name)
  (hash-set! session-tool-usage name (add1 (hash-ref session-tool-usage name 0))))

(define (execute-tool name args)
  (log-debug 2 'tool "CALLED: ~a\n  Args: ~v" name args)
  (record-tool-call! name)
  (define start-time (current-inexact-milliseconds))
  (tool-start! name #:params args)
  (with-handlers ([exn:fail? (λ (e)
                               (log-debug 1 'tool "ERROR: ~a failed: ~a" name (exn-message e))
                               (tool-error! name (exn-message e))
                               (format "Tool Error: ~a" (exn-message e)))])
    (define result
      (cond
        [(string-prefix? name "rdf_") (execute-rdf-tool name args)]
        [(string-prefix? name "web_") (execute-web-search name args)]
        [(string-prefix? name "service_") (if (>= (current-security-level) 2)
                                              (match name ["service_start" (spawn-service! (hash-ref args 'id) (hash-ref args 'cmd) api-key)]
                                                ["service_stop" (stop-service! (hash-ref args 'id))] ["service_list" (list-services!)])
                                              "Requires Level 2.")]
        [else (match name
                ["ask_human" (printf "\n[ASK]: ~a\n> " (hash-ref args 'question)) (read-line)]
                ["ctx_evolve" (gepa-evolve! (hash-ref args 'feedback) (hash-ref args 'model (get-default-model)))]
                ["meta_evolve" (gepa-meta-evolve! (hash-ref args 'feedback) (hash-ref args 'model (get-default-model)))]
                ["run_racket" (run-tiered-code! (hash-ref args 'code) (current-security-level))]
                ["read_file" (if (or (>= (current-security-level) 1) (string-contains? (hash-ref args 'path) ".agentd/workspace"))
                                 (if (file-exists? (hash-ref args 'path)) (file->string (hash-ref args 'path)) "404") "Permission Denied.")]
                ["write_file" (if (>= (current-security-level) 2)
                                  (begin
                                    (when (< (current-security-level) 4) (confirm-risk! "WRITE" (hash-ref args 'path)))
                                    (if (llm-judge-param)
                                        (let-values ([(safe? reason) (evaluate-safety "write_file" (format "File: ~a\nContent:\n~a" (hash-ref args 'path) (hash-ref args 'content)))])
                                          (if safe?
                                              (begin (display-to-file (hash-ref args 'content) (hash-ref args 'path) #:exists 'replace) "Written.")
                                              (format "Security Judge Blocked Action: ~a" reason)))
                                        (begin (display-to-file (hash-ref args 'content) (hash-ref args 'path) #:exists 'replace) "Written.")))
                                  "Permission Denied: Requires Level 2.")]
                ["run_term" (if (>= (current-security-level) 3)
                                (begin
                                  (when (< (current-security-level) 4) (confirm-risk! "TERM" (hash-ref args 'cmd)))
                                  (if (llm-judge-param)
                                      (let-values ([(safe? reason) (evaluate-safety "run_term" (hash-ref args 'cmd))])
                                        (if safe?
                                            (with-output-to-string (λ () (system (hash-ref args 'cmd))))
                                            (format "Security Judge Blocked Action: ~a" reason)))
                                      (with-output-to-string (λ () (system (hash-ref args 'cmd))))))
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
                ["set_priority"
                 (define p (hash-ref args 'priority))
                 (save-ctx! (let ([db (load-ctx)]) (hash-set db 'items (hash-set (hash-ref db 'items) (hash-ref db 'active) (struct-copy Ctx (ctx-get-active) [priority (string->symbol p)])))))
                 (format "Priority set to ~a." p)]
                [_ (format "Unknown: ~a" name)]
                )]))
    (tool-complete! name result #:duration-ms (- (current-inexact-milliseconds) start-time))
    result))

(define (get-tools mode)
  (define mem-tools (list (hash 'type "function" 'function (hash 'name "memory_save" 'parameters (hash 'type "object" 'properties (hash 'text (hash 'type "string")))))
                          (hash 'type "function" 'function (hash 'name "memory_recall" 'parameters (hash 'type "object" 'properties (hash 'query (hash 'type "string")))))
                          (hash 'type "function" 'function (hash 'name "set_priority" 'description "Set the agent's performance profile (best, cheap, fast, verbose). Use this if you want to optimize for speed or cost based on the task." 'parameters (hash 'type "object" 'properties (hash 'priority (hash 'type "string" 'enum '("best" "cheap" "fast" "verbose"))))))))

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
  (define tools-raw (match mode
                      ['ask base]
                      ['architect (append base (list (first fs)))] ; read only
                      ['code (append base fs term (get-supervisor-tools) (make-rdf-tools) (make-web-search-tools) mem-tools)]
                      ['semantic (append base (make-rdf-tools) mem-tools)]
                      [_ base]))
  ;; Filter out any invalid entries (empty lists or non-hashes)
  (define tools (filter (λ (t) (and (hash? t) (hash-has-key? t 'function))) tools-raw))
  (log-debug/once 1 'tools "Available tools: ~a" (map (λ (t) (hash-ref (hash-ref t 'function) 'name)) tools))
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
      (responses-run-turn/stream #:api-key api-key #:make-request mk-req #:emit! emit! #:tool-emit! tool-emit! #:tool-run execute-tool #:cancelled? cancelled? #:api-base (base-url-param)))

    (define in-tok (hash-ref usage 'prompt_tokens 0))
    (define out-tok (hash-ref usage 'completion_tokens 0))
    (define cost (calculate-cost current-model in-tok out-tok))
    
    ;; Update session stats using setter functions from runtime.rkt
    (session-add-cost! cost)
    (session-add-tokens! in-tok out-tok)
    (session-increment-turns!)
    (session-record-model-usage! current-model in-tok out-tok cost)

    (session-stats-add-turn! #:tokens-in in-tok #:tokens-out out-tok #:cost cost)

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

;; Functions imported from commands.rkt:
;; - generate-session-title, handle-new-session, create-new-session!, 
;;   resume-last-session!, resume-session-by-id!, list-sessions!, list-threads!
;;   display-figlet-banner, print-session-summary!, handle-slash-command

;; Functions imported from runtime.rkt:
;; - levenshtein, format-duration, format-number
;; - session-start-time, session-input-tokens, session-output-tokens, 
;;   session-turn-count, session-model-usage, session-tool-usage, total-session-cost

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

(define (check-env-verbose!)
  "Check all environment variables and show critical errors in verbose debug mode"
  (when (>= (current-debug-level) 2)
    (log-section "Environment Variables Check")
    (define required-vars (list "OPENAI_API_KEY"))
    (define optional-vars (list "OPENAI_API_BASE" "MODEL" "VISION_MODEL" "BUDGET" "TIMEOUT" "PRIORITY" "LLM_JUDGE" "LLM_JUDGE_MODEL" "INTERACTIVE" "PRETTY" "CHRYSALIS_PORT" "CHRYSALIS_HOST"))

    (define missing-required '())
    (define missing-optional '())

    (for ([var required-vars])
      (define val (getenv var))
      (if val
          (let ([preview (if (> (string-length val) 8)
                             (format "~a...~a" (substring val 0 8) (substring val (max 0 (- (string-length val) 4))))
                             (format "~a..." (substring val 0 (min 4 (string-length val)))))])
            (log-debug 2 'env (format "✓ ~a: SET (~a)" var preview)))
          (begin
            (set! missing-required (cons var missing-required))
            (eprintf "[CRITICAL ERROR] Required environment variable ~a is NOT SET~n" var)
            (eprintf "  Set it with: export ~a=<value>~n" var)
            (eprintf "  Or use: /config <key> <value> in interactive mode~n"))))

    (for ([var optional-vars])
      (define val (getenv var))
      (if val
          (log-debug 2 'env (format "✓ ~a: ~a" var val))
          (begin
            (set! missing-optional (cons var missing-optional))
            (log-debug 2 'env (format "○ ~a: not set (using default)" var)))))

    (when (not (null? missing-required))
      (newline)
      (eprintf "[CRITICAL] Missing required environment variables:~n")
      (for ([var missing-required])
        (eprintf "  - ~a~n" var))
      (eprintf "~nPlease set these variables before continuing.~n")
      (eprintf "You can set them with:~n")
      (eprintf "  export OPENAI_API_KEY=sk-...~n")
      (eprintf "Or use the --api-key flag or /config command.~n~n"))

    (when (not (null? missing-optional))
      (log-debug 2 'env (format "Optional variables not set: ~a" (string-join missing-optional ", "))))

    (newline)))

;; handle-slash-command is imported from commands.rkt, but we wrap it to inject acp-run-turn
(define (main-handle-slash-command cmd input)
  (handle-slash-command cmd input #:run-turn acp-run-turn))

;; Removed ~410 lines of duplicate code:
;; - handle-slash-command (full definition) - now in commands.rkt
;; - format-duration, format-number - now in runtime.rkt  
;; - print-session-summary! - now in commands.rkt
;; - with-raw-terminal, read-multiline-input, read-bracket-seq - now in repl.rkt
;; - Old repl-loop definition - now using modular repl-loop from repl.rkt

;; The main-repl-loop wraps the modular repl-loop with dependency injection
(define (main-repl-loop)
  (repl-loop #:run-turn acp-run-turn
             #:check-env-verbose! check-env-verbose!
             #:verify-env! verify-env!
             #:session-action-param session-action-param
             #:list-sessions! list-sessions!
             #:resume-last-session! resume-last-session!
             #:resume-session-by-id! resume-session-by-id!
             #:create-new-session! create-new-session!
             #:display-figlet-banner display-figlet-banner
             #:handle-new-session handle-new-session
             #:handle-slash-command main-handle-slash-command
             #:print-session-summary! print-session-summary!
             #:use-animated-intro? #t
             #:api-key env-api-key))

(define mode-param (make-parameter 'run))
(command-line #:program "chrysalis"
              #:once-each
              [("--gui") "Launch GUI" (mode-param 'gui)]
              [("--acp") "Run ACP Server" (mode-param 'acp)]
              [("--acp-port") port "ACP Port (default: stdio)" (acp-port-param port)]
              [("-P" "--perms") p "Security Level (0, 1, 2, 3, god)"
                           (match p
                             ["0" (current-security-level 0)]
                             ["1" (current-security-level 1)]
                             ["2" (current-security-level 2)]
                             ["3" (current-security-level 3)]
                             ["god" (current-security-level 4)]
                             [_ (error "Invalid permission level. Use 0, 1, 2, 3, or god.")])]

              [("-d" "--debug") level "Set Debug Level (0, 1, 2, verbose)"
                                (let ([val (string->number level)])
                                  (cond
                                    [(equal? level "verbose") (current-debug-level 2)]
                                    [val (current-debug-level val)]
                                    [else (current-debug-level 1)]))]
              [("-m" "--model") m "Set LLM Model (e.g., gpt-5.2, o1-preview)" (model-param m)]
              [("-p" "--priority") p "Set Runtime Priority (e.g., 'fast', 'cheap', or 'I need accuracy')" (priority-param p)]
              [("-i" "--interactive") "Enter Interactive Mode" (interactive-param #t)]
              ;; Service mode options
              [("--serve") "Start HTTP service" (mode-param 'serve)]
              [("--serve-port") port "Service port (default: 8080)" (serve-port-param (string->number port))]
              [("--serve-host") host "Service bind address (default: 127.0.0.1)" (serve-host-param host)]
              [("--daemonize") "Run as background daemon" (daemon-param #t)]
              [("--config") path "Config file path (default: chrysalis.toml)" (config-path-param path)]
              ;; Client mode options
              [("--client") "Connect to a running Chrysalis service" (mode-param 'client)]
              [("--url") url "Service URL to connect to (default: http://127.0.0.1:8080)" (client-url-param url)]
              [("--api-key") key "API key or token for authentication" (client-api-key-param key)]
              ;; Session management options
              [("--session") action "Session action: 'resume' (resume last), '<id>' (resume by ID), 'list' (list sessions)" 
                           (session-action-param action)]
              #:args raw-args
              (match (mode-param)
                ['gui
                 ;; GUI Mode - Launch graphical interface
                 (define gui-mod (dynamic-require 'chrysalis-forge/src/gui/main-gui 'run-gui!))
                 (gui-mod)]
                ['run (begin
                        (check-env-verbose!)
                        (if (or (interactive-param) (null? raw-args))
                            (main-repl-loop)
                            (begin
                              (verify-env! #:fail #t)
                              (let ([task (string-join raw-args " ")])
                                (save-ctx! (let ([db (load-ctx)]) (hash-set db 'items (hash-set (hash-ref db 'items) (hash-ref db 'active) (struct-copy Ctx (ctx-get-active) [mode 'code] [priority (string->symbol (priority-param))])))))
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
                ['acp
                 (eprintf "~n====================================~n")
                 (eprintf "Chrysalis Forge ACP Server~n")
                 (eprintf "====================================~n")
                 (eprintf "Transport: ~a~n" (acp-port-param))
                 (eprintf "Model: ~a~n" (model-param))
                 (eprintf "Security Level: ~a~n" (current-security-level))
                 (eprintf "Priority: ~a~n" (priority-param))
                 (eprintf "====================================~n")
                 (eprintf "Listening for JSON-RPC messages...~n~n")
                 (acp-serve #:modes ACP-MODES #:on-new-session handle-new-session #:run-turn acp-run-turn)]
                ['serve
                 ;; HTTP Service Mode
                 (if (daemon-param)
                     (run-daemon!)
                     (start-service! #:port (serve-port-param) #:host (serve-host-param)))]
                ['client
                 ;; Client Mode - Connect to running service
                 (client-repl (client-url-param) #:api-key (client-api-key-param))]))
