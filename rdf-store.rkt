#lang racket/base
(provide (all-defined-out))
(require db racket/file racket/string racket/list json)

(define DB-PATH (build-path (find-system-path 'home-dir) ".agentd" "graph.db"))

;; Ensure DB exists
(make-directory* (build-path (find-system-path 'home-dir) ".agentd"))
(define (get-db)
  (define conn (sqlite3-connect #:database DB-PATH #:mode 'create))
  (unless (table-exists? conn "triples")
    (query-exec conn "CREATE TABLE triples (subject TEXT, predicate TEXT, object TEXT)"))
  conn)

(define (rdf-load! path id) 
  ;; Mock implementation for file loading. In a real scenario, this would parse triples.
  ;; For now, we'll just log it.
  (printf "[DB] Would load ~a into graph ~a\n" path id)
  "Loaded (Mock).")

(define (rdf-query q id)
  ;; For now, interpret simple SELECT * queries or just run raw SQL if it starts with SELECT
  (define conn (get-db))
  (define rows
    (if (string-prefix? (string-upcase q) "SELECT")
        (query-rows conn q)
        ;; Default: return all triples if not a SQL query (mocking SPARQL behavior roughly)
        (query-rows conn "SELECT * FROM triples LIMIT 10")))
  
  (define (row->hash r)
    ;; Convert vector row to hash
    (hash 'result (vector->list r)))
  
  (jsexpr->string (map row->hash rows)))

(define (rdf-insert! s p o)
  (define conn (get-db))
  (query-exec conn "INSERT INTO triples (subject, predicate, object) VALUES (?, ?, ?)" s p o))