#lang racket/base
;; Thread Manager
;; High-level abstraction that hides sessions from users.
;; All agent code should talk to threads, not sessions.

(provide (all-defined-out))

(require racket/match
         json
         "../service/db.rkt"
         "../llm/openai-client.rkt")

;; ============================================================================
;; Thread Manager - Core API
;; ============================================================================

;; Configuration for session rotation
(define MAX-SESSION-MESSAGES 100)  ; Rotate after N messages
(define MAX-SESSION-TOKENS 80000)  ; Rotate after N tokens (rough estimate)

;; ----------------------------------------------------------------------------
;; Thread Lifecycle
;; ----------------------------------------------------------------------------

(define (ensure-thread user-id #:thread-id [thread-id #f] #:project-id [project-id #f] 
                       #:title [title #f] #:parent-thread-id [parent-thread-id #f])
  "Get or create a thread. Returns thread hash.
   - If thread-id provided, looks it up
   - Otherwise creates a new thread (optionally as child of parent-thread-id)"
  (cond
    [thread-id
     (or (thread-find-by-id thread-id)
         (error 'ensure-thread "Thread not found: ~a" thread-id))]
    [else
     (define new-id (thread-create! user-id #:project-id project-id #:title title))
     ;; If parent specified, create child_of relation
     (when parent-thread-id
       (thread-relation-create! new-id parent-thread-id "child_of" user-id))
     (thread-find-by-id new-id)]))

(define (thread-continue user-id from-thread-id #:title [title #f] #:project-id [project-id #f])
  "Create a new thread that continues from an existing one.
   Copies summary from old thread to provide continuity."
  (define old-thread (thread-find-by-id from-thread-id))
  (unless old-thread
    (error 'thread-continue "Source thread not found: ~a" from-thread-id))
  
  (define new-id (thread-create! user-id 
                                 #:project-id (or project-id (hash-ref old-thread 'project_id #f))
                                 #:title (or title (format "Continues: ~a" (hash-ref old-thread 'title "Untitled")))))
  
  ;; Create continues_from relation
  (thread-relation-create! new-id from-thread-id "continues_from" user-id)
  
  ;; Copy summary to new thread for context
  (when (hash-ref old-thread 'summary #f)
    (thread-update! new-id #:summary (hash-ref old-thread 'summary)))
  
  (thread-find-by-id new-id))

(define (thread-spawn-child user-id parent-thread-id title #:project-id [project-id #f])
  "Create a child thread for drilling down into a subtopic."
  (define parent (thread-find-by-id parent-thread-id))
  (unless parent
    (error 'thread-spawn-child "Parent thread not found: ~a" parent-thread-id))
  
  (define new-id (thread-create! user-id
                                 #:project-id (or project-id (hash-ref parent 'project_id #f))
                                 #:title title))
  (thread-relation-create! new-id parent-thread-id "child_of" user-id)
  (thread-find-by-id new-id))

(define (thread-link! from-id to-id user-id #:type [type "relates_to"])
  "Create a relation between two threads.
   Valid types: continues_from, child_of, relates_to"
  (unless (member type '("continues_from" "child_of" "relates_to"))
    (error 'thread-link! "Invalid relation type: ~a" type))
  (thread-relation-create! from-id to-id type user-id))

;; ----------------------------------------------------------------------------
;; Session Management (hidden from user)
;; ----------------------------------------------------------------------------

(define (get-or-create-session user-id thread-id #:mode [mode "code"] #:org-id [org-id #f])
  "Get the active session for a thread, or create one if none exists.
   Sessions are an implementation detail - users never see session IDs."
  (or (thread-get-active-session thread-id)
      (session-create-for-thread! user-id thread-id #:org-id org-id #:mode mode)))

(define (rotate-session! user-id thread-id summary-text #:mode [mode "code"] #:org-id [org-id #f])
  "Rotate to a new session while preserving thread continuity.
   - Archives the old session
   - Updates thread summary
   - Creates a fresh session
   Called automatically when session gets too long."
  ;; Archive current session
  (define old-session-id (thread-get-active-session thread-id))
  (when old-session-id
    (session-archive! old-session-id))
  
  ;; Update thread summary for continuity
  (when summary-text
    (thread-update! thread-id #:summary summary-text))
  
  ;; Create new session
  (session-create-for-thread! user-id thread-id #:org-id org-id #:mode mode))

(define (should-rotate-session? thread-id)
  "Check if the current session should be rotated based on heuristics.
   Returns #f or a reason string."
  (define session-id (thread-get-active-session thread-id))
  (unless session-id
    (values #f #f))
  
  (define messages (session-get-messages session-id #:limit 200))
  (define msg-count (length messages))
  (define total-tokens 
    (for/sum ([m messages])
      (+ (or (hash-ref m 'tokens_in #f) 0)
         (or (hash-ref m 'tokens_out #f) 0))))
  
  (cond
    [(>= msg-count MAX-SESSION-MESSAGES)
     (format "Message count (~a) exceeds limit" msg-count)]
    [(>= total-tokens MAX-SESSION-TOKENS)
     (format "Token count (~a) exceeds limit" total-tokens)]
    [else #f]))

;; ----------------------------------------------------------------------------
;; Hierarchical Context API
;; ----------------------------------------------------------------------------

(define (thread-add-context! thread-id title #:parent-id [parent-id #f] #:kind [kind "note"]
                             #:body [body #f] #:files [files '()])
  "Add a context node to a thread for hierarchical breakdown.
   Kind: note, task, area, file_group, plan"
  (thread-context-create! thread-id title
                          #:parent-id parent-id
                          #:kind kind
                          #:body body
                          #:metadata (hash 'files files)))

(define (thread-get-context-hierarchy thread-id)
  "Get the full context tree for a thread."
  (thread-context-tree thread-id))

(define (thread-get-context-path thread-id context-id)
  "Get the path from root to a specific context node (for breadcrumbs)."
  (define (find-path nodes target-id path)
    (for/or ([n nodes])
      (cond
        [(equal? (hash-ref n 'id) target-id)
         (reverse (cons n path))]
        [(hash-has-key? n 'children)
         (find-path (hash-ref n 'children) target-id (cons n path))]
        [else #f])))
  (find-path (thread-context-tree thread-id) context-id '()))

;; ----------------------------------------------------------------------------
;; Thread Discovery & Navigation
;; ----------------------------------------------------------------------------

(define (thread-get-related thread-id)
  "Get all threads related to this one, organized by relation type."
  (define relations (thread-relations-for-thread thread-id))
  
  (define (collect-by-type type direction)
    (for/list ([r relations]
               #:when (equal? (hash-ref r 'relation_type) type))
      (define other-id 
        (if (equal? direction 'from)
            (hash-ref r 'from_thread_id)
            (hash-ref r 'to_thread_id)))
      (if (equal? other-id thread-id)
          (hash-ref r (if (equal? direction 'from) 'to_thread_id 'from_thread_id))
          other-id)))
  
  (hash 'continues_from (collect-by-type "continues_from" 'to)    ; threads this continues from
        'continued_by (collect-by-type "continues_from" 'from)    ; threads that continue this
        'parent (let ([p (thread-get-parent thread-id)]) (if p (list p) '()))
        'children (thread-get-children thread-id)
        'related (collect-by-type "relates_to" 'from)))

(define (thread-get-lineage thread-id)
  "Get the full lineage of a thread (follows continues_from chain)."
  (define (follow-back tid acc)
    (define relations (thread-relations-for-thread tid))
    (define prev 
      (for/or ([r relations])
        (and (equal? (hash-ref r 'relation_type) "continues_from")
             (equal? (hash-ref r 'from_thread_id) tid)
             (hash-ref r 'to_thread_id))))
    (if prev
        (follow-back prev (cons prev acc))
        (reverse acc)))
  (follow-back thread-id (list thread-id)))

;; ----------------------------------------------------------------------------
;; High-Level Chat Entry Point
;; ----------------------------------------------------------------------------

(define (thread-chat-prepare user-id prompt
                             #:thread-id [thread-id #f]
                             #:project-id [project-id #f]
                             #:mode [mode "code"]
                             #:org-id [org-id #f]
                             #:context-node-id [context-node-id #f])
  "Prepare for a chat turn on a thread. Returns:
   - thread: the thread hash
   - session-id: the active session to use
   - context: any context node content to inject
   - rotation-needed: #f or reason string if session should rotate after
   
   This is called by the main agent loop before invoking the LLM."
  (define thread (ensure-thread user-id #:thread-id thread-id #:project-id project-id))
  (define tid (hash-ref thread 'id))
  (define session-id (get-or-create-session user-id tid #:mode mode #:org-id org-id))
  
  ;; Get context if specified
  (define context-content
    (and context-node-id
         (let ([ctx (thread-context-find-by-id context-node-id)])
           (and ctx
                (hash 'title (hash-ref ctx 'title)
                      'body (hash-ref ctx 'body #f)
                      'path (thread-get-context-path tid context-node-id))))))
  
  ;; Check if rotation needed
  (define rotation-reason (should-rotate-session? tid))
  
  (hash 'thread thread
        'session_id session-id
        'context context-content
        'rotation_needed rotation-reason))

(define (thread-chat-finalize! user-id thread-id rotation-reason summary-fn
                               #:mode [mode "code"] #:org-id [org-id #f])
  "Called after a chat turn if rotation was needed.
   summary-fn should be a thunk that generates a summary of the conversation so far."
  (when rotation-reason
    (define summary (summary-fn))
    (rotate-session! user-id thread-id summary #:mode mode #:org-id org-id)))

;; ----------------------------------------------------------------------------
;; Auto-Summarization for Session Rotation
;; ----------------------------------------------------------------------------

(define (generate-thread-summary thread-id #:api-key [api-key #f] #:api-base [api-base "https://api.openai.com/v1"] #:model [model "gpt-4o-mini"])
  "Generate a summary of the thread's current session for rotation.
   Uses a fast/cheap model by default since this is overhead."
  (define session-id (thread-get-active-session thread-id))
  (if (not session-id)
      ""
      (let ([messages (session-get-messages session-id #:limit 100)])
        (if (null? messages)
            ""
            (summarize-conversation messages #:model model #:api-key api-key #:api-base api-base)))))

(define (auto-rotate-if-needed! user-id thread-id 
                                 #:api-key [api-key #f] 
                                 #:api-base [api-base "https://api.openai.com/v1"]
                                 #:mode [mode "code"]
                                 #:org-id [org-id #f])
  "Check if rotation is needed and perform it automatically with summarization."
  (define reason (should-rotate-session? thread-id))
  (when reason
    (define summary (generate-thread-summary thread-id #:api-key api-key #:api-base api-base))
    (rotate-session! user-id thread-id summary #:mode mode #:org-id org-id)
    reason))
