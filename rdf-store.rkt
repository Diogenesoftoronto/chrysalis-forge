#lang racket/base
(provide (all-defined-out))
(require db racket/file racket/string racket/list json racket/match "debug.rkt")

(define DB-PATH (build-path (find-system-path 'home-dir) ".agentd" "graph.db"))

;; Ensure DB exists
(make-directory* (build-path (find-system-path 'home-dir) ".agentd"))
(define (get-db)
  (define conn (sqlite3-connect #:database DB-PATH #:mode 'create))
  (unless (table-exists? conn "triples")
    (query-exec conn "CREATE TABLE triples (subject TEXT, predicate TEXT, object TEXT)"))
  conn)

(define (rdf-load! path id) 
  (log-debug 1 'rdf "Loading triples from ~a..." path)
  (if (file-exists? path)
      (let ([conn (get-db)]
            [lines (file->lines path)])
        (query-exec conn "BEGIN TRANSACTION")
        (for ([line lines])
          (define parts (string-split line))
          (when (>= (length parts) 3)
            (query-exec conn "INSERT INTO triples (subject, predicate, object) VALUES (?, ?, ?)" 
                        (first parts) (second parts) (third parts))))
        (query-exec conn "COMMIT")
        (format "Loaded ~a lines into graph ~a." (length lines) id))
      "File not found."))

(define (rdf-query q id)
  (log-debug 1 'rdf "Query: ~a" q)
  ;; For now, interpret simple SELECT * queries or just run raw SQL if it starts with SELECT
  (define conn (get-db))
  (define rows
    (cond
      [(string-prefix? (string-upcase q) "SELECT") (query-rows conn q)]
      [(string-contains? q "?") 
       ;; Simple pattern matching: ?s p o or s ?p o etc.
       (define parts (string-split q))
       (match parts
         [(list "?s" p o) (query-rows conn "SELECT subject, predicate, object FROM triples WHERE predicate=? AND object=?" p o)]
         [(list s "?p" o) (query-rows conn "SELECT subject, predicate, object FROM triples WHERE subject=? AND object=?" s o)]
         [(list s p "?o") (query-rows conn "SELECT subject, predicate, object FROM triples WHERE subject=? AND predicate=?" s p)]
         [_ (query-rows conn "SELECT * FROM triples LIMIT 20")])]
      [else (query-rows conn "SELECT * FROM triples LIMIT 20")]))
  
  (define (row->hash r)
    ;; Convert vector row to hash
    (hash 'result (vector->list r)))
  
  (define res (jsexpr->string (map row->hash rows)))
  (log-debug 2 'rdf "Query Result size: ~a bytes" (string-length res))
  res)

(define (rdf-insert! s p o)
  (log-debug 1 'rdf "Insert: ~a ~a ~a" s p o)
  (define conn (get-db))
  (query-exec conn "INSERT INTO triples (subject, predicate, object) VALUES (?, ?, ?)" s p o))