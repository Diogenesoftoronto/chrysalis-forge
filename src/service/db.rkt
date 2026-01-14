#lang racket/base
;; Chrysalis Forge Database Operations
;; SQLite database connection and query utilities

(provide (all-defined-out))

(require db racket/string racket/file racket/match json racket/list racket/path)
(require "config.rkt")

;; ============================================================================
;; Database Connection Management
;; ============================================================================

(define current-db-connection (make-parameter #f))

(define (get-db-path)
  "Get the database file path from configuration"
  (define url (config-database-url))
  (cond
    [(string-prefix? url "sqlite:///") (substring url 10)]
    [(string-prefix? url "sqlite://") (substring url 9)]
    [else url]))

(define (init-database!)
  "Initialize database connection and ensure schema exists"
  (define db-path (get-db-path))
  
  ;; Ensure directory exists
  (define db-dir (path-only db-path))
  (when db-dir
    (make-directory* db-dir))
  
  ;; Connect to database
  (define conn (sqlite3-connect #:database db-path #:mode 'create))
  (current-db-connection conn)
  
  ;; Enable foreign keys
  (query-exec conn "PRAGMA foreign_keys = ON")
  
  ;; Run schema if tables don't exist
  (unless (table-exists? conn "users")
    (run-schema! conn))
  
  (eprintf "[DB] Connected to ~a~n" db-path)
  conn)

(define (get-db)
  "Get current database connection, initializing if needed"
  (or (current-db-connection)
      (init-database!)))

(define (close-database!)
  "Close the database connection"
  (when (current-db-connection)
    (disconnect (current-db-connection))
    (current-db-connection #f)))

;; ============================================================================
;; Schema Management
;; ============================================================================

(define (table-exists? conn table-name)
  "Check if a table exists in the database"
  (define result 
    (query-maybe-row conn 
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?"
      table-name))
  (and result #t))

(define (run-schema! conn)
  "Execute the schema SQL file"
  (define schema-path 
    (build-path (path-only (path->complete-path (current-directory)))
                "src" "service" "schema.sql"))
  
  (define schema-sql
    (if (file-exists? schema-path)
        (file->string schema-path)
        ;; Fallback: try relative to this file
        (let ([alt-path (build-path (path-only (syntax-source #'here)) "schema.sql")])
          (if (file-exists? alt-path)
              (file->string alt-path)
              (error 'run-schema! "Cannot find schema.sql")))))
  
  ;; Split and execute statements
  (for ([stmt (string-split schema-sql ";")])
    (define trimmed (string-trim stmt))
    (when (> (string-length trimmed) 0)
      (with-handlers ([exn:fail? (λ (e) 
                                   (eprintf "[DB SCHEMA] Warning: ~a~n" (exn-message e)))])
        (query-exec conn trimmed))))
  
  (eprintf "[DB] Schema initialized~n"))

(define (get-schema-version conn)
  "Get current schema version"
  (define result (query-maybe-value conn "SELECT MAX(version) FROM schema_migrations"))
  (or result 0))

;; ============================================================================
;; Query Helpers
;; ============================================================================

(define (uuid)
  "Generate a UUID v4"
  (define bytes (crypto-random-bytes 16))
  (format "~a~a~a~a-~a~a-4~a~a-~a~a~a~a-~a~a~a~a~a~a"
          (byte->hex (bytes-ref bytes 0)) (byte->hex (bytes-ref bytes 1))
          (byte->hex (bytes-ref bytes 2)) (byte->hex (bytes-ref bytes 3))
          (byte->hex (bytes-ref bytes 4)) (byte->hex (bytes-ref bytes 5))
          (byte->hex (bytes-ref bytes 6)) (byte->hex (bytes-ref bytes 7))
          (byte->hex (bitwise-ior #x80 (bitwise-and #x3f (bytes-ref bytes 8))))
          (byte->hex (bytes-ref bytes 9)) (byte->hex (bytes-ref bytes 10))
          (byte->hex (bytes-ref bytes 11)) (byte->hex (bytes-ref bytes 12))
          (byte->hex (bytes-ref bytes 13)) (byte->hex (bytes-ref bytes 14))
          (byte->hex (bytes-ref bytes 15))))

(define (byte->hex b)
  (define hex "0123456789abcdef")
  (string (string-ref hex (quotient b 16))
          (string-ref hex (remainder b 16))))

(define (crypto-random-bytes n)
  "Generate cryptographically random bytes"
  (define bs (make-bytes n))
  (for ([i (in-range n)])
    (bytes-set! bs i (random 256)))
  bs)

(define (hash->json h)
  "Convert hash to JSON string for storage"
  (jsexpr->string h))

(define (json->hash s)
  "Parse JSON string to hash"
  (if (or (not s) (equal? s ""))
      (hash)
      (with-handlers ([exn:fail? (λ (_) (hash))])
        (string->jsexpr s))))

(define (row->hash row columns)
  "Convert a database row to a hash using column names"
  (for/hash ([col columns] [val (vector->list row)])
    (values col val)))

;; ============================================================================
;; User Operations
;; ============================================================================

(define (user-create! email password-hash #:display-name [display-name #f])
  "Create a new user and return their ID"
  (define conn (get-db))
  (define id (uuid))
  (query-exec conn
    "INSERT INTO users (id, email, password_hash, display_name) VALUES (?, ?, ?, ?)"
    id email password-hash display-name)
  id)

(define (user-find-by-email email)
  "Find user by email, returns hash or #f"
  (define conn (get-db))
  (define row (query-maybe-row conn
    "SELECT id, email, password_hash, display_name, avatar_url, created_at, last_login, email_verified, status 
     FROM users WHERE email = ?" email))
  (and row
       (row->hash row '(id email password_hash display_name avatar_url created_at last_login email_verified status))))

(define (user-find-by-id id)
  "Find user by ID"
  (define conn (get-db))
  (define row (query-maybe-row conn
    "SELECT id, email, password_hash, display_name, avatar_url, created_at, last_login, email_verified, status 
     FROM users WHERE id = ?" id))
  (and row
       (row->hash row '(id email password_hash display_name avatar_url created_at last_login email_verified status))))

(define (user-update-login! user-id)
  "Update user's last login timestamp"
  (define conn (get-db))
  (query-exec conn "UPDATE users SET last_login = CURRENT_TIMESTAMP WHERE id = ?" user-id))

(define (user-update! user-id #:display-name [display-name #f] #:avatar-url [avatar-url #f])
  "Update user profile"
  (define conn (get-db))
  (when display-name
    (query-exec conn "UPDATE users SET display_name = ? WHERE id = ?" display-name user-id))
  (when avatar-url
    (query-exec conn "UPDATE users SET avatar_url = ? WHERE id = ?" avatar-url user-id)))

;; ============================================================================
;; Organization Operations
;; ============================================================================

(define (org-create! name slug owner-id #:settings [settings (hash)])
  "Create a new organization"
  (define conn (get-db))
  (define id (uuid))
  (query-exec conn
    "INSERT INTO organizations (id, name, slug, owner_id, settings) VALUES (?, ?, ?, ?, ?)"
    id name slug owner-id (hash->json settings))
  ;; Add owner as member
  (query-exec conn
    "INSERT INTO org_members (org_id, user_id, role) VALUES (?, ?, 'owner')"
    id owner-id)
  id)

(define (org-find-by-slug slug)
  "Find organization by slug"
  (define conn (get-db))
  (define row (query-maybe-row conn
    "SELECT id, name, slug, owner_id, created_at, settings FROM organizations WHERE slug = ?" slug))
  (and row
       (let ([h (row->hash row '(id name slug owner_id created_at settings))])
         (hash-set h 'settings (json->hash (hash-ref h 'settings))))))

(define (org-find-by-id id)
  "Find organization by ID"
  (define conn (get-db))
  (define row (query-maybe-row conn
    "SELECT id, name, slug, owner_id, created_at, settings FROM organizations WHERE id = ?" id))
  (and row
       (let ([h (row->hash row '(id name slug owner_id created_at settings))])
         (hash-set h 'settings (json->hash (hash-ref h 'settings))))))

(define (org-list-for-user user-id)
  "List all organizations a user belongs to"
  (define conn (get-db))
  (define rows (query-rows conn
    "SELECT o.id, o.name, o.slug, o.owner_id, m.role 
     FROM organizations o
     JOIN org_members m ON o.id = m.org_id
     WHERE m.user_id = ?" user-id))
  (for/list ([row rows])
    (row->hash row '(id name slug owner_id role))))

(define (org-get-members org-id)
  "Get all members of an organization"
  (define conn (get-db))
  (define rows (query-rows conn
    "SELECT u.id, u.email, u.display_name, u.avatar_url, m.role, m.joined_at
     FROM users u
     JOIN org_members m ON u.id = m.user_id
     WHERE m.org_id = ?" org-id))
  (for/list ([row rows])
    (row->hash row '(id email display_name avatar_url role joined_at))))

(define (org-add-member! org-id user-id role #:invited-by [invited-by #f])
  "Add a member to an organization"
  (define conn (get-db))
  (query-exec conn
    "INSERT INTO org_members (org_id, user_id, role, invited_by) VALUES (?, ?, ?, ?)"
    org-id user-id role invited-by))

(define (org-user-role org-id user-id)
  "Get user's role in an organization, or #f if not a member"
  (define conn (get-db))
  (query-maybe-value conn
    "SELECT role FROM org_members WHERE org_id = ? AND user_id = ?" org-id user-id))

;; ============================================================================
;; API Key Operations
;; ============================================================================

(define (api-key-create! user-id name key-hash prefix #:org-id [org-id #f] #:expires-at [expires-at #f])
  "Create a new API key"
  (define conn (get-db))
  (define id (uuid))
  (query-exec conn
    "INSERT INTO api_keys (id, user_id, org_id, name, key_hash, prefix, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?)"
    id user-id org-id name key-hash prefix expires-at)
  id)

(define (api-key-find-by-prefix prefix)
  "Find API key by prefix (first 8 chars)"
  (define conn (get-db))
  (define row (query-maybe-row conn
    "SELECT id, user_id, org_id, name, key_hash, prefix, scopes, created_at, last_used, expires_at
     FROM api_keys WHERE prefix = ?" prefix))
  (and row
       (row->hash row '(id user_id org_id name key_hash prefix scopes created_at last_used expires_at))))

(define (api-key-update-last-used! key-id)
  "Update API key's last used timestamp"
  (define conn (get-db))
  (query-exec conn "UPDATE api_keys SET last_used = CURRENT_TIMESTAMP WHERE id = ?" key-id))

(define (api-key-list-for-user user-id)
  "List all API keys for a user"
  (define conn (get-db))
  (define rows (query-rows conn
    "SELECT id, name, prefix, scopes, created_at, last_used, expires_at
     FROM api_keys WHERE user_id = ?" user-id))
  (for/list ([row rows])
    (row->hash row '(id name prefix scopes created_at last_used expires_at))))

(define (api-key-delete! key-id)
  "Delete an API key"
  (define conn (get-db))
  (query-exec conn "DELETE FROM api_keys WHERE id = ?" key-id))

;; ============================================================================
;; Provider Key (BYOK) Operations
;; ============================================================================

(define (provider-key-add! user-id provider key-encrypted #:org-id [org-id #f] #:base-url [base-url #f] #:key-hint [key-hint #f])
  "Add or update a provider key"
  (define conn (get-db))
  (define id (uuid))
  ;; Use INSERT OR REPLACE for upsert behavior
  (query-exec conn
    "INSERT OR REPLACE INTO provider_keys (id, user_id, org_id, provider, key_encrypted, key_hint, base_url, validated_at, is_valid)
     VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, TRUE)"
    id user-id org-id provider key-encrypted key-hint base-url)
  id)

(define (provider-key-get user-id provider #:org-id [org-id #f])
  "Get a provider key for a user/org"
  (define conn (get-db))
  ;; Try user's personal key first, then org key
  (define personal-row (query-maybe-row conn
    "SELECT id, user_id, org_id, provider, key_encrypted, key_hint, base_url, is_valid
     FROM provider_keys WHERE user_id = ? AND provider = ? AND org_id IS NULL" user-id provider))
  
  (define org-row 
    (and org-id
         (not personal-row)
         (query-maybe-row conn
           "SELECT id, user_id, org_id, provider, key_encrypted, key_hint, base_url, is_valid
            FROM provider_keys WHERE org_id = ? AND provider = ?" org-id provider)))
  
  (define row (or personal-row org-row))
  (and row
       (row->hash row '(id user_id org_id provider key_encrypted key_hint base_url is_valid))))

(define (provider-key-list-for-user user-id)
  "List all provider keys for a user"
  (define conn (get-db))
  (define rows (query-rows conn
    "SELECT id, provider, key_hint, base_url, is_valid, created_at, validated_at
     FROM provider_keys WHERE user_id = ? AND org_id IS NULL" user-id))
  (for/list ([row rows])
    (row->hash row '(id provider key_hint base_url is_valid created_at validated_at))))

;; ============================================================================
;; Session Operations
;; ============================================================================

(define (session-create! user-id #:org-id [org-id #f] #:mode [mode "code"] #:title [title #f])
  "Create a new agent session"
  (define conn (get-db))
  (define id (uuid))
  (query-exec conn
    "INSERT INTO sessions (id, user_id, org_id, mode, title) VALUES (?, ?, ?, ?, ?)"
    id user-id org-id mode title)
  id)

(define (session-find-by-id id)
  "Find session by ID"
  (define conn (get-db))
  (define row (query-maybe-row conn
    "SELECT id, user_id, org_id, mode, title, created_at, updated_at, context, is_archived
     FROM sessions WHERE id = ?" id))
  (and row
       (let ([h (row->hash row '(id user_id org_id mode title created_at updated_at context is_archived))])
         (hash-set h 'context (json->hash (hash-ref h 'context))))))

(define (session-list-for-user user-id #:limit [limit 50] #:include-archived [include-archived #f])
  "List sessions for a user"
  (define conn (get-db))
  (define query 
    (if include-archived
        "SELECT id, mode, title, created_at, updated_at, is_archived FROM sessions WHERE user_id = ? ORDER BY updated_at DESC LIMIT ?"
        "SELECT id, mode, title, created_at, updated_at, is_archived FROM sessions WHERE user_id = ? AND is_archived = FALSE ORDER BY updated_at DESC LIMIT ?"))
  (define rows (query-rows conn query user-id limit))
  (for/list ([row rows])
    (row->hash row '(id mode title created_at updated_at is_archived))))

(define (session-add-message! session-id role content #:tool-calls [tool-calls #f] #:tool-call-id [tool-call-id #f] 
                              #:model [model #f] #:tokens-in [tokens-in #f] #:tokens-out [tokens-out #f] #:cost-usd [cost-usd #f])
  "Add a message to a session"
  (define conn (get-db))
  (query-exec conn
    "INSERT INTO session_messages (session_id, role, content, tool_calls, tool_call_id, model, tokens_in, tokens_out, cost_usd)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
    session-id role content (and tool-calls (hash->json tool-calls)) tool-call-id model tokens-in tokens-out cost-usd)
  ;; Update session timestamp
  (query-exec conn "UPDATE sessions SET updated_at = CURRENT_TIMESTAMP WHERE id = ?" session-id))

(define (session-get-messages session-id #:limit [limit 100])
  "Get messages for a session"
  (define conn (get-db))
  (define rows (query-rows conn
    "SELECT id, role, content, tool_calls, tool_call_id, model, tokens_in, tokens_out, cost_usd, created_at
     FROM session_messages WHERE session_id = ? ORDER BY id LIMIT ?" session-id limit))
  (for/list ([row rows])
    (let ([h (row->hash row '(id role content tool_calls tool_call_id model tokens_in tokens_out cost_usd created_at))])
      (hash-set h 'tool_calls (json->hash (hash-ref h 'tool_calls))))))

;; ============================================================================
;; Usage Tracking
;; ============================================================================

(define (usage-log! user-id model provider input-tokens output-tokens cost-usd 
                    #:org-id [org-id #f] #:session-id [session-id #f] 
                    #:provider-key-id [provider-key-id #f] #:is-byok [is-byok #f])
  "Log usage for billing and analytics"
  (define conn (get-db))
  (query-exec conn
    "INSERT INTO usage_logs (user_id, org_id, session_id, model, provider, input_tokens, output_tokens, cost_usd, provider_key_id, is_byok)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
    user-id org-id session-id model provider input-tokens output-tokens cost-usd provider-key-id (if is-byok 1 0)))

(define (usage-get-daily user-id date #:org-id [org-id #f])
  "Get daily usage summary"
  (define conn (get-db))
  (define row (query-maybe-row conn
    "SELECT messages, tokens, cost_usd FROM usage_daily 
     WHERE user_id = ? AND date = ? AND (org_id = ? OR (org_id IS NULL AND ? IS NULL))"
    user-id date org-id org-id))
  (if row
      (row->hash row '(messages tokens cost_usd))
      (hash 'messages 0 'tokens 0 'cost_usd 0.0)))

(define (usage-increment-daily! user-id date tokens cost-usd #:org-id [org-id #f])
  "Increment daily usage counters"
  (define conn (get-db))
  (query-exec conn
    "INSERT INTO usage_daily (user_id, org_id, date, messages, tokens, cost_usd)
     VALUES (?, ?, ?, 1, ?, ?)
     ON CONFLICT(user_id, COALESCE(org_id, ''), date) 
     DO UPDATE SET messages = messages + 1, tokens = tokens + ?, cost_usd = cost_usd + ?"
    user-id org-id date tokens cost-usd tokens cost-usd))

;; ============================================================================
;; Project Operations
;; ============================================================================

(define (project-create! user-id name #:org-id [org-id #f] #:slug [slug #f] 
                         #:description [description #f] #:settings [settings (hash)])
  "Create a new project"
  (define conn (get-db))
  (define id (uuid))
  (query-exec conn
    "INSERT INTO projects (id, org_id, owner_id, slug, name, description, settings)
     VALUES (?, ?, ?, ?, ?, ?, ?)"
    id org-id user-id slug name description (hash->json settings))
  id)

(define (project-find-by-id id)
  "Find project by ID"
  (define conn (get-db))
  (define row (query-maybe-row conn
    "SELECT id, org_id, owner_id, slug, name, description, settings, created_at, updated_at, is_archived
     FROM projects WHERE id = ?" id))
  (and row
       (let ([h (row->hash row '(id org_id owner_id slug name description settings created_at updated_at is_archived))])
         (hash-set h 'settings (json->hash (hash-ref h 'settings))))))

(define (project-list-for-user user-id #:org-id [org-id #f] #:limit [limit 50])
  "List projects for a user"
  (define conn (get-db))
  (define rows 
    (if org-id
        (query-rows conn
          "SELECT id, org_id, slug, name, description, created_at, updated_at, is_archived
           FROM projects WHERE org_id = ? AND is_archived = FALSE ORDER BY updated_at DESC LIMIT ?"
          org-id limit)
        (query-rows conn
          "SELECT id, org_id, slug, name, description, created_at, updated_at, is_archived
           FROM projects WHERE owner_id = ? AND is_archived = FALSE ORDER BY updated_at DESC LIMIT ?"
          user-id limit)))
  (for/list ([row rows])
    (row->hash row '(id org_id slug name description created_at updated_at is_archived))))

(define (project-update! id #:name [name #f] #:description [description #f] #:settings [settings #f])
  "Update project"
  (define conn (get-db))
  (when name
    (query-exec conn "UPDATE projects SET name = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?" name id))
  (when description
    (query-exec conn "UPDATE projects SET description = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?" description id))
  (when settings
    (query-exec conn "UPDATE projects SET settings = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?" (hash->json settings) id)))

;; ============================================================================
;; Thread Operations
;; ============================================================================

(define (thread-id-generate)
  "Generate a thread ID in T-uuid format"
  (format "T-~a" (uuid)))

(define (thread-create! user-id #:org-id [org-id #f] #:project-id [project-id #f]
                        #:title [title #f] #:metadata [metadata (hash)])
  "Create a new thread"
  (define conn (get-db))
  (define id (thread-id-generate))
  (query-exec conn
    "INSERT INTO threads (id, user_id, org_id, project_id, title, metadata)
     VALUES (?, ?, ?, ?, ?, ?)"
    id user-id org-id project-id title (hash->json metadata))
  id)

(define (thread-find-by-id id)
  "Find thread by ID"
  (define conn (get-db))
  (define row (query-maybe-row conn
    "SELECT id, user_id, org_id, project_id, title, status, summary, metadata, created_at, updated_at
     FROM threads WHERE id = ?" id))
  (and row
       (let ([h (row->hash row '(id user_id org_id project_id title status summary metadata created_at updated_at))])
         (hash-set h 'metadata (json->hash (hash-ref h 'metadata))))))

(define (thread-list-for-user user-id #:project-id [project-id #f] #:status [status #f] #:limit [limit 50])
  "List threads for a user, optionally filtered by project"
  (define conn (get-db))
  (define base-query "SELECT id, project_id, title, status, summary, created_at, updated_at FROM threads WHERE user_id = ?")
  (define query-parts (list base-query))
  (define params (list user-id))
  
  (when project-id
    (set! query-parts (append query-parts '(" AND project_id = ?")))
    (set! params (append params (list project-id))))
  (when status
    (set! query-parts (append query-parts '(" AND status = ?")))
    (set! params (append params (list status))))
  (set! query-parts (append query-parts '(" ORDER BY updated_at DESC LIMIT ?")))
  (set! params (append params (list limit)))
  
  (define rows (apply query-rows conn (apply string-append query-parts) params))
  (for/list ([row rows])
    (row->hash row '(id project_id title status summary created_at updated_at))))

(define (thread-update! id #:title [title #f] #:status [status #f] #:summary [summary #f] #:metadata [metadata #f])
  "Update thread fields"
  (define conn (get-db))
  (when title
    (query-exec conn "UPDATE threads SET title = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?" title id))
  (when status
    (query-exec conn "UPDATE threads SET status = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?" status id))
  (when summary
    (query-exec conn "UPDATE threads SET summary = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?" summary id))
  (when metadata
    (query-exec conn "UPDATE threads SET metadata = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?" (hash->json metadata) id)))

(define (thread-touch! id)
  "Update thread's updated_at timestamp"
  (define conn (get-db))
  (query-exec conn "UPDATE threads SET updated_at = CURRENT_TIMESTAMP WHERE id = ?" id))

;; ============================================================================
;; Thread Relation Operations
;; ============================================================================

(define (thread-relation-create! from-id to-id relation-type created-by)
  "Create a relation between threads"
  (define conn (get-db))
  (define id (uuid))
  (query-exec conn
    "INSERT INTO thread_relations (id, from_thread_id, to_thread_id, relation_type, created_by)
     VALUES (?, ?, ?, ?, ?)"
    id from-id to-id relation-type created-by)
  id)

(define (thread-relations-for-thread thread-id)
  "Get all relations involving a thread"
  (define conn (get-db))
  (define rows (query-rows conn
    "SELECT id, from_thread_id, to_thread_id, relation_type, created_by, created_at
     FROM thread_relations WHERE from_thread_id = ? OR to_thread_id = ?"
    thread-id thread-id))
  (for/list ([row rows])
    (row->hash row '(id from_thread_id to_thread_id relation_type created_by created_at))))

(define (thread-get-parent thread-id)
  "Get parent thread if this is a child"
  (define conn (get-db))
  (define row (query-maybe-row conn
    "SELECT to_thread_id FROM thread_relations 
     WHERE from_thread_id = ? AND relation_type = 'child_of'" thread-id))
  (and row (vector-ref row 0)))

(define (thread-get-children thread-id)
  "Get child threads"
  (define conn (get-db))
  (define rows (query-rows conn
    "SELECT from_thread_id FROM thread_relations 
     WHERE to_thread_id = ? AND relation_type = 'child_of'" thread-id))
  (for/list ([row rows]) (vector-ref row 0)))

;; ============================================================================
;; Thread Context Node Operations
;; ============================================================================

(define (thread-context-create! thread-id title #:parent-id [parent-id #f] #:kind [kind "note"]
                                #:body [body #f] #:metadata [metadata (hash)] #:sort-order [sort-order 0])
  "Create a context node within a thread"
  (define conn (get-db))
  (define id (uuid))
  (query-exec conn
    "INSERT INTO thread_contexts (id, thread_id, parent_id, title, kind, body, metadata, sort_order)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
    id thread-id parent-id title kind body (hash->json metadata) sort-order)
  id)

(define (thread-context-find-by-id id)
  "Find a context node by ID"
  (define conn (get-db))
  (define row (query-maybe-row conn
    "SELECT id, thread_id, parent_id, title, kind, body, metadata, sort_order, created_at, updated_at
     FROM thread_contexts WHERE id = ?" id))
  (and row
       (let ([h (row->hash row '(id thread_id parent_id title kind body metadata sort_order created_at updated_at))])
         (hash-set h 'metadata (json->hash (hash-ref h 'metadata))))))

(define (thread-context-list thread-id)
  "Get all context nodes for a thread as a flat list"
  (define conn (get-db))
  (define rows (query-rows conn
    "SELECT id, parent_id, title, kind, body, metadata, sort_order, created_at, updated_at
     FROM thread_contexts WHERE thread_id = ? ORDER BY sort_order, created_at" thread-id))
  (for/list ([row rows])
    (let ([h (row->hash row '(id parent_id title kind body metadata sort_order created_at updated_at))])
      (hash-set h 'metadata (json->hash (hash-ref h 'metadata))))))

(define (thread-context-tree thread-id)
  "Build a tree structure from context nodes"
  (define nodes (thread-context-list thread-id))
  (define by-id (for/hash ([n nodes]) (values (hash-ref n 'id) n)))
  (define children-map (make-hash))
  
  ;; Group nodes by parent
  (for ([n nodes])
    (define parent (hash-ref n 'parent_id #f))
    (hash-update! children-map parent (λ (lst) (cons n lst)) '()))
  
  ;; Build tree recursively
  (define (build-subtree node)
    (define children (reverse (hash-ref children-map (hash-ref node 'id) '())))
    (hash-set node 'children (map build-subtree children)))
  
  ;; Return roots (nodes with no parent)
  (map build-subtree (reverse (hash-ref children-map #f '()))))

(define (thread-context-update! id #:title [title #f] #:body [body #f] #:kind [kind #f] #:metadata [metadata #f])
  "Update a context node"
  (define conn (get-db))
  (when title
    (query-exec conn "UPDATE thread_contexts SET title = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?" title id))
  (when body
    (query-exec conn "UPDATE thread_contexts SET body = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?" body id))
  (when kind
    (query-exec conn "UPDATE thread_contexts SET kind = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?" kind id))
  (when metadata
    (query-exec conn "UPDATE thread_contexts SET metadata = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?" (hash->json metadata) id)))

;; ============================================================================
;; Session-Thread Linkage (Extended)
;; ============================================================================

(define (session-create-for-thread! user-id thread-id #:org-id [org-id #f] #:mode [mode "code"])
  "Create a session linked to a thread"
  (define conn (get-db))
  (define id (uuid))
  ;; Note: Requires sessions table to have thread_id column (migration v2)
  (query-exec conn
    "INSERT INTO sessions (id, user_id, org_id, mode, thread_id) VALUES (?, ?, ?, ?, ?)"
    id user-id org-id mode thread-id)
  ;; Touch thread
  (thread-touch! thread-id)
  id)

(define (session-list-for-thread thread-id #:limit [limit 10])
  "List sessions belonging to a thread"
  (define conn (get-db))
  (define rows (query-rows conn
    "SELECT id, mode, title, created_at, updated_at, is_archived
     FROM sessions WHERE thread_id = ? ORDER BY updated_at DESC LIMIT ?"
    thread-id limit))
  (for/list ([row rows])
    (row->hash row '(id mode title created_at updated_at is_archived))))

(define (thread-get-active-session thread-id)
  "Get the most recent active session for a thread"
  (define conn (get-db))
  (query-maybe-value conn
    "SELECT id FROM sessions WHERE thread_id = ? AND is_archived = FALSE ORDER BY updated_at DESC LIMIT 1"
    thread-id))

(define (session-archive! session-id)
  "Archive a session"
  (define conn (get-db))
  (query-exec conn "UPDATE sessions SET is_archived = TRUE, updated_at = CURRENT_TIMESTAMP WHERE id = ?" session-id))
