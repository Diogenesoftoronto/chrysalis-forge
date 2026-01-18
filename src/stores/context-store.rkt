#lang racket/base
(provide (all-defined-out))
(provide session-create! session-switch! session-list session-delete!
         session-get-metadata session-list-with-metadata session-get-last
         session-resume-by-id session-update-title!)
(require json
         racket/file
         racket/date
         racket/list
         racket/random
         "../llm/dspy-core.rkt")

(define DB-PATH (build-path (find-system-path 'home-dir) ".agentd" "context.json"))

(define (default-db/json)
  ;; Default DB in the same shape as the JSON on disk:
  ;; - 'active is a string
  ;; - 'items maps symbols -> ctx JSON hashes (not Ctx structs)
  ;; NOTE: Racket's `write-json` expects hash keys to be symbols.
  (define default-ctx (Ctx (default-system-prompt) "" "" 'ask 'best '() ""))
  (hash 'active "default"
        'items (hash 'default (ctx->json default-ctx))
        'metadata (hash)))

(define (default-db/mem)
  ;; Default DB in the in-memory shape used by the app:
  ;; - 'active is a symbol
  ;; - 'items maps symbols -> Ctx structs
  (hash 'active 'default
        'items (hash 'default (Ctx (default-system-prompt) "" "" 'ask 'best '() ""))
        'metadata (hash)))

;; Best-effort JSON read: if file is corrupt, back it up and start fresh.
(define (read-db-or-recover!)
  (with-handlers ([exn:fail?
                   (λ (e)
                     (define backup-path
                       (path-replace-extension
                        DB-PATH
                        (format ".corrupt-~a.json" (current-seconds))))
                     (with-handlers ([exn:fail? (λ (_) (void))])
                       (when (file-exists? DB-PATH)
                         (copy-file DB-PATH backup-path #t)))
                     (default-db/json))])
    (call-with-input-file DB-PATH (λ (in) (read-json in)))))

;; Generate a UUID v4-like string
(define (generate-session-id)
  (define (random-hex n)
    (apply string-append (for/list ([i (in-range n)])
                           (format "~x" (random 16)))))
  (format "~a-~a-~a-~a-~a"
          (random-hex 8)
          (random-hex 4)
          (random-hex 4)
          (random-hex 4)
          (random-hex 12)))

(define (json->ctx j)
  (define prio-raw (hash-ref j 'priority "best"))
  ;; Support both symbol keywords and NL strings
  (define prio (if (member prio-raw '("best" "fast" "cheap" "compact" "verbose"))
                   (string->symbol prio-raw)
                   prio-raw)) ;; Keep as string for NL dispatch
  (Ctx (hash-ref j 'system) (hash-ref j 'memory) (hash-ref j 'tool_hints) (string->symbol (hash-ref j 'mode "ask")) prio (hash-ref j 'history '()) (hash-ref j 'compacted_summary "")))

(define (ctx->json c)
  (define prio (Ctx-priority c))
  (hash 'system (Ctx-system c) 'memory (Ctx-memory c) 'tool_hints (Ctx-tool-hints c) 'mode (symbol->string (Ctx-mode c)) 'priority (if (symbol? prio) (symbol->string prio) prio) 'history (Ctx-history c) 'compacted_summary (Ctx-compacted-summary c)))

(define (default-system-prompt)
  (format #<<EOF
You are agentd, an AI agent. Your task is to analyze content and assist the user.

<capabilities>
You HAVE access to real-time information via the `web_search` tool.
You MUST use `web_search` when asked about current events, weather, news, or any information not in your training data.
DO NOT say "I don't have access" or "I cannot browse". You DO have these capabilities. USE THEM.
</capabilities>

<rules>
1. Be concise and direct in your responses
2. Focus only on the information requested in the user's prompt
3. If the content is provided in a file path, use the grep and view tools to efficiently search through it
4. When relevant, quote specific sections from the content to support your answer
5. If the requested information is not found, clearly state that
6. Any file paths you use MUST be absolute
7. **IMPORTANT**: If you need information from a linked page or search result, use the web_fetch tool to get that content
8. **IMPORTANT**: If you need to search for more information, use the web_search tool or web_search_news
9. After fetching a link, analyze the content yourself to extract what's needed
10. Don't hesitate to follow multiple links or perform multiple searches if necessary to get complete information
11. **CRITICAL**: At the end of your response, include a "Sources" section listing ALL URLs that were useful in answering the question
</rules>

<env>
Working directory: ~a
Platform: ~a
Today's date: ~a
</env>
EOF
          (current-directory)
          (system-type 'os)
          (parameterize ([date-display-format 'iso-8601]) (date->string (current-date)))))

;; Load context with backward compatibility
(define (load-ctx)
  (cond
    [(file-exists? DB-PATH)
     (define db (read-db-or-recover!))
     (define active-sym (string->symbol (hash-ref db 'active)))
     (define items-hash/raw (hash-ref db 'items (hash)))
     (define metadata/raw (hash-ref db 'metadata (hash)))
     ;; Back-compat: allow string keys on disk, normalize to symbols in memory.
     (define metadata
       (for/hash ([(k v) metadata/raw])
         (values (if (symbol? k) k (string->symbol k)) v)))
     ;; Convert old format (direct Ctx) to new format (with metadata)
     (define converted-items
       (for/hash ([(k v) items-hash/raw])
         (define ksym (if (symbol? k) k (string->symbol k)))
         (cond
           ;; Already in-memory Ctx (legacy / bad writes) — pass through.
           [(Ctx? v)
            (values ksym v)]
           ;; New format: has 'ctx' key (shouldn't happen in current implementation)
           [(and (hash? v) (hash-has-key? v 'ctx))
            (values ksym (json->ctx (hash-ref v 'ctx)))]
           ;; Old format: direct Ctx data
           [else
            (values ksym (json->ctx v))])))
     (hash 'active active-sym
           'items converted-items
           'metadata metadata)]
    [else
     (default-db/mem)]))

;; Save context with metadata
(define (save-ctx! db)
  (make-directory* (build-path (find-system-path 'home-dir) ".agentd"))
  (define items-hash (hash-ref db 'items))
  (define metadata-hash (hash-ref db 'metadata (hash)))
  ;; Convert to JSON format: store Ctx in 'ctx' key, metadata separately
  (define json-items
    (for/hash ([(k v) items-hash])
      ;; Keep keys as symbols for `write-json`.
      (values k (ctx->json v))))
  (define json-db (hash 'active (symbol->string (hash-ref db 'active))
                        'items json-items
                        'metadata metadata-hash))
  ;; Atomic write to avoid truncation/corruption on crash.
  (define tmp-path (path-replace-extension DB-PATH ".tmp"))
  (call-with-output-file tmp-path
    (λ (out) (write-json json-db out))
    #:exists 'truncate/replace)
  (rename-file-or-directory tmp-path DB-PATH #t))

(define (ctx-get-active)
  (define db (load-ctx))
  (define base-ctx (hash-ref (hash-ref db 'items) (hash-ref db 'active)))
  ;; Check for project-specific rules
  (define rules-path (build-path (current-directory) ".agentd" "rules.md"))
  (if (file-exists? rules-path)
      (let ([rules-content (file->string rules-path)])
        (struct-copy Ctx base-ctx
                     [system (string-append (Ctx-system base-ctx)
                                            "\n\n<project_rules>\n"
                                            rules-content
                                            "\n</project_rules>")]))
      base-ctx))

(define (session-list)
  (define db (load-ctx))
  (values (hash-keys (hash-ref db 'items)) (hash-ref db 'active)))

;; Get session metadata by session name (symbol)
(define (session-get-metadata session-name)
  (define db (load-ctx))
  (define metadata (hash-ref db 'metadata (hash)))
  (hash-ref metadata session-name #f))

;; List sessions with metadata
(define (session-list-with-metadata)
  (define db (load-ctx))
  (define items (hash-ref db 'items))
  (define metadata (hash-ref db 'metadata (hash)))
  (define active (hash-ref db 'active))
  (for/list ([session-name (hash-keys items)])
    (define name-str (symbol->string session-name))
    (define meta (hash-ref metadata session-name (hash)))
    (hash 'name name-str
          'id (hash-ref meta 'id name-str)
          'title (hash-ref meta 'title #f)
          'created_at (hash-ref meta 'created_at #f)
          'updated_at (hash-ref meta 'updated_at #f)
          'is_active (equal? session-name active))))

;; Get the last session (most recently updated)
(define (session-get-last)
  (define sessions (session-list-with-metadata))
  (if (null? sessions)
      #f
      (let ([sorted (sort sessions > #:key (λ (s) (or (hash-ref s 'updated_at #f) 0)))])
        (hash-ref (first sorted) 'id))))

;; Resume session by ID
(define (session-resume-by-id session-id)
  (define sessions (session-list-with-metadata))
  (define found
    (for/or ([s sessions])
      (and (equal? (hash-ref s 'id) session-id)
           (hash-ref s 'name))))
  (if found
      (begin
        (session-switch! found)
        found)
      #f))

;; Update session title
(define (session-update-title! session-name title)
  (define db (load-ctx))
  (define metadata (hash-ref db 'metadata (hash)))
  (define name-sym (if (symbol? session-name) session-name (string->symbol session-name)))
  (define existing-meta (hash-ref metadata name-sym (hash)))
  (define updated-meta (hash-set (hash-set existing-meta 'title title)
                                 'updated_at (current-seconds)))
  (save-ctx! (hash-set db 'metadata (hash-set metadata name-sym updated-meta))))

(define (session-create! name [mode 'code] #:id [id #f] #:title [title #f])
  (define db (load-ctx))
  (define items (hash-ref db 'items))
  (define metadata (hash-ref db 'metadata (hash)))
  (define name-sym (if (symbol? name) name (string->symbol name)))
  (if (hash-has-key? items name-sym)
      (error "Session already exists")
      (let* ([session-id (or id (generate-session-id))]
             [now (current-seconds)]
             [new-meta (hash 'id session-id
                            'title title
                            'created_at now
                            'updated_at now)])
        (save-ctx! (hash-set (hash-set db 'items (hash-set items name-sym (Ctx (default-system-prompt) "" "" mode 'best '() "")))
                            'metadata (hash-set metadata name-sym new-meta))))))

(define (session-switch! name)
  (define db (load-ctx))
  (define items (hash-ref db 'items))
  (define name-sym (if (symbol? name) name (string->symbol name)))
  (if (hash-has-key? items name-sym)
      (let* ([db-updated (hash-set db 'active name-sym)]
             [metadata (hash-ref db-updated 'metadata (hash))]
             [existing-meta (hash-ref metadata name-sym (hash))]
             [updated-meta (hash-set existing-meta 'updated_at (current-seconds))])
        (save-ctx! (hash-set db-updated 'metadata (hash-set metadata name-sym updated-meta))))
      (error "Session not found")))

(define (session-delete! name)
  (define db (load-ctx))
  (define items (hash-ref db 'items))
  (define name-sym (if (symbol? name) name (string->symbol name)))
  (if (equal? name-sym (hash-ref db 'active))
      (error "Cannot delete active session")
      (if (hash-has-key? items name-sym)
          (let ([metadata (hash-ref db 'metadata (hash))])
            (save-ctx! (hash-set (hash-set db 'items (hash-remove items name-sym))
                                'metadata (hash-remove metadata name-sym))))
          (error "Session not found"))))