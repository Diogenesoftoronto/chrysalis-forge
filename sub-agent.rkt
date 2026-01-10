#lang racket
(provide spawn-sub-agent! await-sub-agent! sub-agent-status make-sub-agent-tools)
(require racket/async-channel json racket/format)

;; Sub-agent registry: id -> (hash 'thread 'channel 'status 'result 'prompt)
(define SUB-AGENTS (make-hash))
(define agent-counter 0)

;; Tool definitions for sub-agent management
(define (make-sub-agent-tools)
  (list
   (hash 'type "function"
         'function (hash 'name "spawn_task"
                         'description "Spawn a parallel sub-agent to work on a task. Returns a task ID."
                         'parameters (hash 'type "object"
                                           'properties (hash 'prompt (hash 'type "string" 'description "The task/prompt for the sub-agent")
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
;; run-fn: (prompt context) -> result (the actual agent execution function)
(define (spawn-sub-agent! prompt run-fn [context ""])
  (set! agent-counter (add1 agent-counter))
  (define id (format "task-~a" agent-counter))
  (define result-channel (make-async-channel))
  
  (define t 
    (thread
     (λ ()
       (with-handlers ([exn:fail? (λ (e) 
                                    (async-channel-put result-channel 
                                                       (hash 'status 'error 'error (exn-message e))))])
         (define result (run-fn prompt context))
         (async-channel-put result-channel (hash 'status 'done 'result result))))))
  
  (hash-set! SUB-AGENTS id 
             (hash 'thread t 
                   'channel result-channel 
                   'status 'running 
                   'prompt prompt
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
                 'result (if (eq? (hash-ref result 'status) 'done) 
                             (hash-ref result 'result) 
                             (hash-ref result 'error))))
         (hash 'status (hash-ref agent 'status)))]
    [else
     (hash 'status 'running 'prompt (hash-ref agent 'prompt))]))

;; Execute sub-agent tool calls
(define (execute-sub-agent-tool name args run-fn)
  (match name
    ["spawn_task"
     (spawn-sub-agent! (hash-ref args 'prompt) run-fn (hash-ref args 'context ""))]
    ["await_task"
     (await-sub-agent! (hash-ref args 'task_id))]
    ["task_status"
     (define status (sub-agent-status (hash-ref args 'task_id)))
     (format "Status: ~a~a" 
             (hash-ref status 'status)
             (if (hash-has-key? status 'result) 
                 (format "\nResult: ~a" (hash-ref status 'result))
                 ""))]
    [_ (format "Unknown sub-agent tool: ~a" name)]))
