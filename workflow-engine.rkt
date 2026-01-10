#lang racket/base
(provide ensure-workflow-table workflow-list workflow-get workflow-set workflow-delete)
(require db racket/string json racket/list)

(define DB-PATH (build-path (find-system-path 'home-dir) ".agentd" "graph.db"))

(define (get-db)
  (define conn (sqlite3-connect #:database DB-PATH #:mode 'create))
  (ensure-workflow-table conn)
  conn)

(define (ensure-workflow-table conn)
  (unless (table-exists? conn "workflows")
    (query-exec conn "CREATE TABLE workflows (slug TEXT PRIMARY KEY, description TEXT, content TEXT)")))

(define (workflow-list)
  (define conn (get-db))
  (define rows (query-rows conn "SELECT slug, description FROM workflows"))
  (define (row->hash r) (hash 'slug (vector-ref r 0) 'description (vector-ref r 1)))
  (jsexpr->string (map row->hash rows)))

(define (workflow-get slug)
  (define conn (get-db))
  (define result (query-maybe-value conn "SELECT content FROM workflows WHERE slug = ?" slug))
  (if (sql-null? result) "null" result))

(define (workflow-set slug description content)
  (define conn (get-db))
  (query-exec conn "INSERT INTO workflows (slug, description, content) VALUES (?, ?, ?) ON CONFLICT(slug) DO UPDATE SET description=excluded.description, content=excluded.content" slug description content)
  "Workflow saved.")

(define (workflow-delete slug)
  (define conn (get-db))
  (query-exec conn "DELETE FROM workflows WHERE slug = ?" slug)
  "Workflow deleted.")

(define DEFAULT-WORKFLOWS
  (hash
   "commit-msg"
   (hash 'description "Generate a Conventional Commit message for staged changes."
         'content "Run `git diff --cached` to see changes. Then generate a commit message following the Conventional Commits specification. Output ONLY the commit message inside a code block.")
   "pr-desc"
   (hash 'description "Generate a Pull Request description."
         'content "Run `git diff main...HEAD` (or appropriate branch) to see changes. Generate a PR description with Summary, Changes, and Impact sections.")
   "review"
   (hash 'description "Perform a code review on staged changes."
         'content "Run `git diff --cached`. Analyze the code for bugs, security issues, and style violations. distinct from syntax errors. Provide specific, actionable feedback.")
   "naming"
   (hash 'description "Suggest names for symbols/files."
         'content "Analyze the code context and suggest clear, idiomatic names for variables, functions, or files. Explain the reasoning.")))

(define (load-workflows) (get-db)) ;; Helper if needed or just use get-db

(define (ensure-default-workflows!)
  (define conn (get-db))
  (for ([(slug data) DEFAULT-WORKFLOWS])
    (define exists (query-maybe-value conn "SELECT 1 FROM workflows WHERE slug = ?" slug))
    (unless exists
      (workflow-set slug (hash-ref data 'description) (hash-ref data 'content)))))

;; Initialize defaults
(ensure-default-workflows!)
