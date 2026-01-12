#lang racket
(require racket/cmdline json racket/file racket/list racket/format "src/core/acp-stdio.rkt" "src/stores/context-store.rkt" "src/llm/dspy-core.rkt"

         "src/utils/dotenv.rkt" "src/llm/openai-responses-stream.rkt" "src/llm/openai-client.rkt"
         "src/tools/acp-tools.rkt" "src/core/optimizer-gepa.rkt" "src/stores/trace-store.rkt" "src/tools/rdf-tools.rkt"
         "src/core/process-supervisor.rkt" "src/tools/sandbox-exec.rkt" "src/utils/debug.rkt" "src/llm/pricing-model.rkt"
         "src/stores/vector-store.rkt" "src/core/workflow-engine.rkt" "src/utils/utils-time.rkt" "src/tools/web-search.rkt"
         "src/stores/eval-store.rkt" "src/tools/mcp-client.rkt" "src/llm/model-registry.rkt")

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

(define api-key (getenv "OPENAI_API_KEY"))
(define env-api-key api-key)
(define base-url-param (make-parameter (or (getenv "OPENAI_API_BASE") "https://api.openai.com/v1")))
(define model-param (make-parameter (get-default-model)))
(define vision-model-param (make-parameter (or (getenv "VISION_MODEL") (get-default-model))))
(define interactive-param (make-parameter (or (getenv "INTERACTIVE") #f)))
(define attachments (make-parameter '())) ; List of (type content) pairs

(define budget-param (make-parameter (or (getenv "BUDGET") +inf.0)))
(define timeout-param (make-parameter (or (getenv "TIMEOUT") +inf.0)))
(define pretty-param (make-parameter (or (getenv "PRETTY") "none")))
(define session-start-time (current-seconds))
(define total-session-cost 0.0)
(define session-input-tokens 0)
(define session-output-tokens 0)
(define session-turn-count 0)
(define session-model-usage (make-hash))
(define session-tool-usage (make-hash))

(define current-security-level (make-parameter 1))
(define priority-param (make-parameter (or (getenv "PRIORITY") "best")))
(define acp-port-param (make-parameter (or (getenv "ACP_PORT") "stdio")))

;; Service mode parameters
(define serve-port-param (make-parameter (or (getenv "CHRYSALIS_PORT") 8080)))
(define serve-host-param (make-parameter (or (getenv "CHRYSALIS_HOST") "127.0.0.1")))
(define daemon-param (make-parameter #f))
(define config-path-param (make-parameter #f))

;; Client mode parameters
(define client-url-param (make-parameter "http://127.0.0.1:8080"))
(define client-api-key-param (make-parameter #f))

(define ACP-MODES
  (list (hash 'slug "ask" 'name "Ask" 'description "Read only.")
        (hash 'slug "architect" 'name "Architect" 'description "Read files.")
        (hash 'slug "code" 'name "Code" 'description "Full FS/Net.")
        (hash 'slug "semantic" 'name "Semantic" 'description "RDF Graph.")))

(define (confirm-risk! action description)
  (printf "\n[ALERT] ~a: ~a. Allow? [y/N]: " action description)
  (flush-output)
  (if (member (string-downcase (or (read-line) "n")) '("y" "yes")) #t (error 'security "Denied.")))

(define llm-judge-param (make-parameter (or (getenv "LLM_JUDGE") #f)))
(define llm-judge-model-param (make-parameter (or (getenv "LLM_JUDGE_MODEL") (get-default-model))))

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
  (with-handlers ([exn:fail? (λ (e) 
                               (log-debug 1 'tool "ERROR: ~a failed: ~a" name (exn-message e))
                               (format "Tool Error: ~a" (exn-message e)))])
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
                                ;; Security Judge Check
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
                              ;; Security Judge Check
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
             )])))

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
      (responses-run-turn/stream #:api-key api-key #:make-request mk-req #:emit! emit! #:tool-run execute-tool #:cancelled? cancelled? #:api-base (base-url-param)))
    
    (define in-tok (hash-ref usage 'prompt_tokens 0))
    (define out-tok (hash-ref usage 'completion_tokens 0))
    (define cost (calculate-cost current-model in-tok out-tok))
    (set! total-session-cost (+ total-session-cost cost))
    
    (set! session-input-tokens (+ session-input-tokens in-tok))
    (set! session-output-tokens (+ session-output-tokens out-tok))
    (set! session-turn-count (add1 session-turn-count))

    ;; Track per-model usage
    (define model-entry (hash-ref session-model-usage current-model (hash 'in 0 'out 0 'calls 0 'cost 0.0)))
    (hash-set! session-model-usage current-model
               (hash 'in (+ (hash-ref model-entry 'in) in-tok)
                     'out (+ (hash-ref model-entry 'out) out-tok)
                     'calls (add1 (hash-ref model-entry 'calls))
                     'cost (+ (hash-ref model-entry 'cost) cost)))

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

(define (display-figlet-banner text font)
  "Display ASCII art banner using figlet. Falls back to plain text if figlet is not available."
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

(define (handle-slash-command cmd input)
  (with-handlers ([exn:fail? (λ (e)
                                (eprintf "[ERROR] Command failed: ~a~n" (exn-message e))
                                (eprintf "Type /help for available commands.~n"))])
    (match cmd
      [(or "exit" "quit") (print-session-summary!) (displayln "Goodbye.") (exit)]
      ["help" (displayln "Commands:\n  /help - Show this message\n  /exit, /quit - Exit\n  /raco <args> - Run raco commands\n  /config list - List current config\n  /config <key> <val> - Set param\n  /models - List available models from API\n  /workflows - List workflows\n  /workflows show <slug> - Show workflow details\n  /workflows delete <slug> - Delete a workflow\n  /init - Initialize project")]
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
        ;; List all current config values
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
        (printf "  Pretty: ~a\n" (pretty-param))
          (printf "  Debug Level: ~a\n" (current-debug-level))]
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
       ;; In a real app we'd base64 encode here, for now assuming path or URL
       ;; For local files, we'd need to implementing base64 reading.
       (attachments (cons (list 'image path) (attachments)))
       (printf "Attached image: ~a\n" path))]
    ["models"
     (printf "Fetching available models from ~a...\n" (base-url-param))
     (with-handlers ([exn:fail? (λ (e)
                                   (eprintf "[ERROR] Failed to fetch models: ~a\n" (exn-message e))
                                   (eprintf "Check your API endpoint and key configuration.\n"))])
       (define models (fetch-models-from-endpoint (base-url-param) api-key))
       (if (null? models)
           (printf "No models found. The API endpoint may not support model listing.\n")
           (begin
             (printf "\nAvailable Models:\n")
             (for ([m models])
               (define model-id (cond
                                  [(hash? m) (hash-ref m 'id (hash-ref m 'name "unknown"))]
                                  [(string? m) m]
                                  [else "unknown"]))
               (printf "  - ~a\n" model-id))
             (printf "\nUse '/config model <name>' to set a model.\n"))))]
    
    ["workflows"
     (define rest (if (>= (string-length input) 10)
                      (string-trim (substring input 10))
                      ""))
     (define parts (if (> (string-length rest) 0)
                       (string-split rest)
                       '()))
     (cond
       [(or (null? parts) (equal? (first parts) "list"))
        ;; List all workflows
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
        ;; Show workflow details
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
        ;; Delete workflow
        (define slug (second parts))
        (with-handlers ([exn:fail? (λ (e)
                                      (eprintf "[ERROR] Failed to delete workflow: ~a\n" (exn-message e)))])
          (define result (workflow-delete slug))
          (printf "~a\n" result))]
       [else
        (displayln "Usage: /workflows [list|show <slug>|delete <slug>]")])]
    
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
       (define candidates '("exit" "quit" "help" "raco" "config" "models" "workflows" "init"))
       (define suggestions (filter (λ (c) (<= (levenshtein cmd c) 2)) candidates))
       (if (not (null? suggestions))
           (printf "Unknown command '/~a'. Did you mean: /~a?\n" cmd (string-join suggestions ", /"))
           (printf "Unknown command '/~a'. Type /help for list.\n" cmd))])))

(define (format-duration seconds)
  (define mins (quotient seconds 60))
  (define secs (remainder seconds 60))
  (if (> mins 0)
      (format "~am ~as" mins secs)
      (format "~as" secs)))

(define (format-number n)
  (define s (number->string n))
  (define len (string-length s))
  (if (<= len 3) s
      (let loop ([i (- len 3)] [acc (substring s (- len 3))])
        (if (<= i 0)
            (string-append (substring s 0 i) acc)
            (loop (- i 3) (string-append "," (substring s (max 0 (- i 3)) i) acc))))))

(define (print-session-summary!)
  (define duration (- (current-seconds) session-start-time))
  (define total-tokens (+ session-input-tokens session-output-tokens))
  
  ;; Get MCP stats
  (define mcp-stats (with-handlers ([exn:fail? (λ (_) (hash 'connections 0 'tool_calls 0 'tool_success 0 'tool_failures 0 'clients (hash)))])
                      (mcp-get-session-stats)))
  
  ;; Get lifetime tool stats from eval-store
  (define lifetime-tools (with-handlers ([exn:fail? (λ (_) (make-hash))])
                           (get-tool-stats)))
  
  (newline)
  (displayln "───────────────────────────── Session Summary ─────────────────────────────")
  (printf "Duration        ~a~n" (format-duration duration))
  (printf "Turns           ~a~n" session-turn-count)
  (newline)
  
  ;; Model usage
  (unless (hash-empty? session-model-usage)
    (displayln "Model Usage:")
    (for ([(model stats) (in-hash session-model-usage)])
      (printf "  ~a    ~a calls   ~a in · ~a out   $~a~n"
              (~a model #:width 16)
              (hash-ref stats 'calls)
              (format-number (hash-ref stats 'in))
              (format-number (hash-ref stats 'out))
              (real->decimal-string (hash-ref stats 'cost) 4)))
    (newline))
  
  ;; Token summary
  (printf "Tokens          ~a input   ~a output   ~a total~n"
          (format-number session-input-tokens)
          (format-number session-output-tokens)
          (format-number total-tokens))
  (printf "Cost            $~a~n" (real->decimal-string total-session-cost 4))
  (newline)
  
  ;; Tool usage
  (unless (hash-empty? session-tool-usage)
    (displayln "Tools Used:")
    (define sorted-tools (sort (hash->list session-tool-usage) > #:key cdr))
    (for ([tool-pair (take sorted-tools (min 10 (length sorted-tools)))])
      (define name (car tool-pair))
      (define count (cdr tool-pair))
      (define lifetime (hash-ref lifetime-tools name 0))
      (printf "  ~a  ~a call~a~a~n"
              (~a name #:width 20)
              count
              (if (= count 1) "" "s")
              (if (> lifetime 0) (format "   (~a lifetime)" lifetime) "")))
    (when (> (length sorted-tools) 10)
      (printf "  ... and ~a more tools~n" (- (length sorted-tools) 10)))
    (newline))
  
  ;; MCP stats
  (when (> (hash-ref mcp-stats 'connections 0) 0)
    (displayln "MCP:")
    (define clients (hash-ref mcp-stats 'clients (hash)))
    (unless (hash-empty? clients)
      (printf "  Clients: ~a~n"
              (string-join (for/list ([(name stats) (in-hash clients)])
                             (format "~a (~a)" name (hash-ref stats 'calls 0)))
                           ", ")))
    (printf "  Tool calls: ~a total   ~a success · ~a failure~n"
            (hash-ref mcp-stats 'tool_calls 0)
            (hash-ref mcp-stats 'tool_success 0)
            (hash-ref mcp-stats 'tool_failures 0))
    (when (> (hash-ref mcp-stats 'connection_failures 0) 0)
      (printf "  Connection failures: ~a~n" (hash-ref mcp-stats 'connection_failures 0)))
    (newline))
  
  (displayln "──────────────────────────────────────────────────────────────────────────"))

(define (repl-loop)
  (check-env-verbose!)
  (verify-env! #:fail #f)
  (display-figlet-banner "chrysalis forge" "standard")
  (newline)
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
         (with-handlers ([exn:fail? (λ (e)
                                       (eprintf "\n[ERROR] ~a\n" (exn-message e))
                                       (eprintf "The REPL will continue. Use /models to list available models.\n"))])
           (acp-run-turn "cli" input (λ (s) (display s) (flush-output)) (λ (_) (void)) (λ () #f)))])
      (loop))))

(define mode-param (make-parameter 'run))
(command-line #:program "chrysalis" 
              #:once-each 
              [("--acp") "Run ACP Server" (mode-param 'acp)]
              [("--acp-port") port "ACP Port (default: stdio)" (acp-port-param port)]
              [("--perms") p "Security Level (0, 1, 2, 3, god)"
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
              #:args raw-args
              (match (mode-param)
                ['run (begin
                        (set! session-start-time (current-seconds)) ;; Reset start time for run
                        (check-env-verbose!)
                        (if (or (interactive-param) (null? raw-args))
                          (repl-loop)
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