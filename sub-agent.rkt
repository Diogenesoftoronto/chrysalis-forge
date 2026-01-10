#lang racket
(provide spawn-sub-agent! await-sub-agent! sub-agent-status 
         make-sub-agent-tools execute-sub-agent-tool
         ;; Tool profiles
         PROFILE-EDITOR PROFILE-RESEARCHER PROFILE-VCS PROFILE-ALL
         get-tool-profile filter-tools-by-names)
(require racket/async-channel json racket/format racket/match)

;; ============================================================================
;; TOOL PROFILES - Pre-defined tool configurations for different sub-agent types
;; ============================================================================

;; Editor agent: File creation and modification
(define PROFILE-EDITOR
  '("read_file" "write_file" "patch_file" "preview_diff" "list_dir"))

;; Researcher agent: Code exploration and search
(define PROFILE-RESEARCHER
  '("read_file" "list_dir" "grep_code" "web_search" "web_fetch" "web_search_news"))

;; VCS agent: Version control operations (git + jj)
(define PROFILE-VCS
  '("git_status" "git_diff" "git_log" "git_commit" "git_checkout"
    "jj_status" "jj_log" "jj_diff" "jj_undo" "jj_op_log" "jj_op_restore"
    "jj_workspace_add" "jj_workspace_list" "jj_describe" "jj_new"))

;; All tools (for backwards compatibility)
(define PROFILE-ALL #f)  ;; #f means no filtering

;; Get a named profile
(define (get-tool-profile name)
  (match name
    ['editor PROFILE-EDITOR]
    ['researcher PROFILE-RESEARCHER]
    ['vcs PROFILE-VCS]
    ['all PROFILE-ALL]
    [_ (error 'get-tool-profile "Unknown profile: ~a" name)]))

;; Filter a list of tools by allowed names
(define (filter-tools-by-names all-tools allowed-names)
  (if (not allowed-names)
      all-tools  ;; No filter, return all
      (filter (λ (tool)
                (define name (hash-ref (hash-ref tool 'function) 'name))
                (member name allowed-names))
              all-tools)))

;; ============================================================================
;; SUB-AGENT MANAGEMENT
;; ============================================================================

;; Sub-agent registry: id -> (hash 'thread 'channel 'status 'result 'prompt 'profile)
(define SUB-AGENTS (make-hash))
(define agent-counter 0)

;; Tool definitions for sub-agent management (with profile support)
(define (make-sub-agent-tools)
  (list
   (hash 'type "function"
         'function (hash 'name "spawn_task"
                         'description "Spawn a parallel sub-agent to work on a task. Returns a task ID. Use 'profile' to limit tools."
                         'parameters (hash 'type "object"
                                           'properties (hash 'prompt (hash 'type "string" 'description "The task/prompt for the sub-agent")
                                                             'profile (hash 'type "string" 'description "Tool profile: 'editor', 'researcher', 'vcs', or 'all' (default: all)")
                                                             'context (hash 'type "string" 'description "Optional additional context"))
                                           'required '("prompt"))))
   (hash 'type "function"
         'function (hash 'name "await_task"
                         'description "Wait for a sub-agent task to complete and get its result."
                         'parameters (hash 'type "object"
                                           'properties (hash 'task_id (hash 'type "string" 'description "The task ID returned by spawn_task"))
                                           'required '("task_id"))))
   (hash 'type "function"
         'function (hash 'name "task_status"
                         'description "Check the status of a sub-agent task without blocking."
                         'parameters (hash 'type "object"
                                           'properties (hash 'task_id (hash 'type "string" 'description "The task ID to check"))
                                           'required '("task_id"))))))

;; Spawn a sub-agent that runs in a separate thread
;; run-fn: (prompt context tools-filter) -> result
;; tools-filter: list of tool names to allow, or #f for all
(define (spawn-sub-agent! prompt run-fn #:context [context ""] #:profile [profile 'all])
  (set! agent-counter (add1 agent-counter))
  (define id (format "task-~a" agent-counter))
  (define result-channel (make-async-channel))
  (define tools-filter (get-tool-profile profile))
  
  (define t 
    (thread
     (λ ()
       (with-handlers ([exn:fail? (λ (e) 
                                    (async-channel-put result-channel 
                                                       (hash 'status 'error 'error (exn-message e))))])
         (define result (run-fn prompt context tools-filter))
         (async-channel-put result-channel (hash 'status 'done 'result result))))))
  
  (hash-set! SUB-AGENTS id 
             (hash 'thread t 
                   'channel result-channel 
                   'status 'running 
                   'prompt prompt
                   'profile profile
                   'result #f))
  id)

;; Wait for a sub-agent to complete (blocking)
(define (await-sub-agent! id)
  (define agent (hash-ref SUB-AGENTS id #f))
  (unless agent (error 'await_task "Unknown task ID: ~a" id))
  
  (define cached-status (hash-ref agent 'status))
  (when (eq? cached-status 'done)
    (hash-ref agent 'result))
  
  ;; Wait for result
  (define result (async-channel-get (hash-ref agent 'channel)))
  (hash-set! SUB-AGENTS id (hash-set* agent 'status (hash-ref result 'status) 'result result))
  
  (if (eq? (hash-ref result 'status) 'done)
      (hash-ref result 'result)
      (format "Task failed: ~a" (hash-ref result 'error))))

;; Check status without blocking
(define (sub-agent-status id)
  (define agent (hash-ref SUB-AGENTS id #f))
  (unless agent (error 'task_status "Unknown task ID: ~a" id))
  
  ;; Check if thread is still alive
  (define t (hash-ref agent 'thread))
  (define alive? (thread-running? t))
  
  (cond
    [(not alive?)
     ;; Thread finished, try to get result
     (define result (async-channel-try-get (hash-ref agent 'channel)))
     (if result
         (begin
           (hash-set! SUB-AGENTS id (hash-set* agent 'status (hash-ref result 'status) 'result result))
           (hash 'status (hash-ref result 'status) 
                 'profile (hash-ref agent 'profile)
                 'result (if (eq? (hash-ref result 'status) 'done) 
                             (hash-ref result 'result) 
                             (hash-ref result 'error))))
         (hash 'status (hash-ref agent 'status) 'profile (hash-ref agent 'profile)))]
    [else
     (hash 'status 'running 'prompt (hash-ref agent 'prompt) 'profile (hash-ref agent 'profile))]))

;; Execute sub-agent tool calls
(define (execute-sub-agent-tool name args run-fn)
  (match name
    ["spawn_task"
     (define profile-str (hash-ref args 'profile "all"))
     (define profile (string->symbol profile-str))
     (spawn-sub-agent! (hash-ref args 'prompt) run-fn 
                       #:context (hash-ref args 'context "")
                       #:profile profile)]
    ["await_task"
     (await-sub-agent! (hash-ref args 'task_id))]
    ["task_status"
     (define status (sub-agent-status (hash-ref args 'task_id)))
     (format "Status: ~a, Profile: ~a~a" 
             (hash-ref status 'status)
             (hash-ref status 'profile)
             (if (hash-has-key? status 'result) 
                 (format "\nResult: ~a" (hash-ref status 'result))
                 ""))]
    [_ (format "Unknown sub-agent tool: ~a" name)]))
