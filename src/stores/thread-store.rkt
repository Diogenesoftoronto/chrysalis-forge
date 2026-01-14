#lang racket/base
;; Local Thread Store
;; Provides thread abstraction for local CLI usage (no multi-user DB).
;; Threads are stored in ~/.chrysalis/threads.json

(provide (all-defined-out))

(require json
         racket/file
         racket/list
         racket/date
         racket/path
         "context-store.rkt")

;; ============================================================================
;; Storage
;; ============================================================================

(define THREADS-PATH (build-path (find-system-path 'home-dir) ".chrysalis" "threads.json"))

(define (ensure-threads-dir!)
  (make-directory* (build-path (find-system-path 'home-dir) ".chrysalis")))

(define (load-threads-db)
  (if (file-exists? THREADS-PATH)
      (with-handlers ([exn:fail? (λ (_) (default-threads-db))])
        (call-with-input-file THREADS-PATH read-json))
      (default-threads-db)))

(define (default-threads-db)
  (hash 'threads (hash)
        'relations '()
        'contexts (hash)
        'active_thread #f))

(define (save-threads-db! db)
  (ensure-threads-dir!)
  (define tmp-path (path-replace-extension THREADS-PATH ".tmp"))
  (call-with-output-file tmp-path
    (λ (out) (write-json db out))
    #:exists 'truncate/replace)
  (rename-file-or-directory tmp-path THREADS-PATH #t))

;; ============================================================================
;; Thread ID Generation
;; ============================================================================

(define (generate-thread-id)
  (define (random-hex n)
    (apply string-append (for/list ([i (in-range n)])
                           (format "~x" (random 16)))))
  (format "T-~a-~a-~a-~a-~a"
          (random-hex 8)
          (random-hex 4)
          (random-hex 4)
          (random-hex 4)
          (random-hex 12)))

;; ============================================================================
;; Thread Operations
;; ============================================================================

(define (local-thread-create! title #:project [project #f])
  "Create a new local thread"
  (define db (load-threads-db))
  (define id (generate-thread-id))
  (define now (current-seconds))
  (define thread-data (hash 'id id
                            'title title
                            'project project
                            'status "active"
                            'summary #f
                            'session_name #f  ;; Links to context-store session
                            'created_at now
                            'updated_at now))
  (define threads (hash-ref db 'threads (hash)))
  (define new-db (hash-set db 'threads (hash-set threads (string->symbol id) thread-data)))
  (save-threads-db! new-db)
  id)

(define (local-thread-find id)
  "Find a thread by ID"
  (define db (load-threads-db))
  (define threads (hash-ref db 'threads (hash)))
  (hash-ref threads (if (symbol? id) id (string->symbol id)) #f))

(define (local-thread-list #:project [project #f] #:status [status #f] #:limit [limit 50])
  "List local threads"
  (define db (load-threads-db))
  (define threads (hash-ref db 'threads (hash)))
  (define all-threads (hash-values threads))
  (define filtered
    (filter (λ (t)
              (and (or (not project) (equal? (hash-ref t 'project #f) project))
                   (or (not status) (equal? (hash-ref t 'status) status))))
            all-threads))
  (define sorted (sort filtered > #:key (λ (t) (hash-ref t 'updated_at 0))))
  (take sorted (min limit (length sorted))))

(define (local-thread-update! id #:title [title #f] #:status [status #f] #:summary [summary #f])
  "Update a thread"
  (define db (load-threads-db))
  (define threads (hash-ref db 'threads (hash)))
  (define id-sym (if (symbol? id) id (string->symbol id)))
  (define thread (hash-ref threads id-sym #f))
  (when thread
    (define updated (hash-set (hash-set thread 'updated_at (current-seconds))
                              'title (or title (hash-ref thread 'title))
                              'status (or status (hash-ref thread 'status))
                              'summary (or summary (hash-ref thread 'summary #f))))
    (save-threads-db! (hash-set db 'threads (hash-set threads id-sym updated)))))

(define (local-thread-get-active)
  "Get the active thread ID"
  (define db (load-threads-db))
  (hash-ref db 'active_thread #f))

(define (local-thread-set-active! id)
  "Set the active thread"
  (define db (load-threads-db))
  (save-threads-db! (hash-set db 'active_thread id)))

;; ============================================================================
;; Thread-Session Linkage
;; ============================================================================

(define (local-thread-get-session thread-id)
  "Get the context-store session name for a thread"
  (define thread (local-thread-find thread-id))
  (and thread (hash-ref thread 'session_name #f)))

(define (local-thread-link-session! thread-id session-name)
  "Link a thread to a context-store session"
  (define db (load-threads-db))
  (define threads (hash-ref db 'threads (hash)))
  (define id-sym (if (symbol? thread-id) thread-id (string->symbol thread-id)))
  (define thread (hash-ref threads id-sym #f))
  (when thread
    (define updated (hash-set thread 'session_name session-name))
    (save-threads-db! (hash-set db 'threads (hash-set threads id-sym updated)))))

(define (local-thread-ensure-session! thread-id #:mode [mode 'code])
  "Ensure a thread has a linked session, create if needed"
  (define existing (local-thread-get-session thread-id))
  (if existing
      existing
      (let* ([session-name (string->symbol (format "thread-~a" thread-id))]
             [thread (local-thread-find thread-id)])
        (session-create! session-name mode #:title (and thread (hash-ref thread 'title #f)))
        (local-thread-link-session! thread-id (symbol->string session-name))
        (symbol->string session-name))))

(define (local-thread-switch! thread-id)
  "Switch to a thread (activates its linked session)"
  (define session-name (local-thread-ensure-session! thread-id))
  (session-switch! session-name)
  (local-thread-set-active! thread-id)
  session-name)

;; ============================================================================
;; Thread Relations
;; ============================================================================

(define (local-thread-relation-create! from-id to-id relation-type)
  "Create a relation between threads"
  (define db (load-threads-db))
  (define relations (hash-ref db 'relations '()))
  (define new-rel (hash 'from from-id 'to to-id 'type relation-type 'created_at (current-seconds)))
  (save-threads-db! (hash-set db 'relations (cons new-rel relations))))

(define (local-thread-get-relations thread-id)
  "Get all relations for a thread"
  (define db (load-threads-db))
  (define relations (hash-ref db 'relations '()))
  (filter (λ (r) (or (equal? (hash-ref r 'from) thread-id)
                     (equal? (hash-ref r 'to) thread-id)))
          relations))

(define (local-thread-continue! from-thread-id #:title [title #f])
  "Create a thread that continues from another"
  (define from-thread (local-thread-find from-thread-id))
  (define new-title (or title (and from-thread (format "Continues: ~a" (hash-ref from-thread 'title "Untitled")))))
  (define new-id (local-thread-create! new-title #:project (and from-thread (hash-ref from-thread 'project #f))))
  (local-thread-relation-create! new-id from-thread-id "continues_from")
  ;; Copy summary for continuity
  (when (and from-thread (hash-ref from-thread 'summary #f))
    (local-thread-update! new-id #:summary (hash-ref from-thread 'summary)))
  new-id)

(define (local-thread-spawn-child! parent-id title)
  "Create a child thread"
  (define parent (local-thread-find parent-id))
  (define new-id (local-thread-create! title #:project (and parent (hash-ref parent 'project #f))))
  (local-thread-relation-create! new-id parent-id "child_of")
  new-id)

;; ============================================================================
;; Thread Context Nodes
;; ============================================================================

(define (local-context-create! thread-id title #:parent [parent-id #f] #:kind [kind "note"] #:body [body #f])
  "Create a context node within a thread"
  (define db (load-threads-db))
  (define contexts (hash-ref db 'contexts (hash)))
  (define id (format "ctx-~a" (random 1000000000)))
  (define node (hash 'id id
                     'thread_id thread-id
                     'parent_id parent-id
                     'title title
                     'kind kind
                     'body body
                     'created_at (current-seconds)))
  (save-threads-db! (hash-set db 'contexts (hash-set contexts (string->symbol id) node)))
  id)

(define (local-context-list thread-id)
  "Get all context nodes for a thread"
  (define db (load-threads-db))
  (define contexts (hash-ref db 'contexts (hash)))
  (filter (λ (c) (equal? (hash-ref c 'thread_id) thread-id))
          (hash-values contexts)))

(define (local-context-tree thread-id)
  "Build a tree from context nodes"
  (define nodes (local-context-list thread-id))
  (define children-map (make-hash))
  (for ([n nodes])
    (define parent (hash-ref n 'parent_id #f))
    (hash-update! children-map parent (λ (lst) (cons n lst)) '()))
  (define (build-subtree node)
    (define children (reverse (hash-ref children-map (hash-ref node 'id) '())))
    (hash-set node 'children (map build-subtree children)))
  (map build-subtree (reverse (hash-ref children-map #f '()))))
