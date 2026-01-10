#lang racket/base
(provide (all-defined-out))
(require db racket/file racket/string racket/list json racket/match "../utils/debug.rkt")

(define DB-PATH (build-path (find-system-path 'home-dir) ".agentd" "graph.db"))

;; Ensure DB exists
(make-directory* (build-path (find-system-path 'home-dir) ".agentd"))
(define (get-db)
  (define conn (sqlite3-connect #:database DB-PATH #:mode 'create))
  (unless (table-exists? conn "triples")
    (query-exec conn "CREATE TABLE triples (subject TEXT, predicate TEXT, object TEXT, graph TEXT DEFAULT 'default', timestamp INTEGER)"))
  
  ;; Migration 1: Add graph column
  (with-handlers ([exn:fail? (lambda (e) (void))])
    (query-exec conn "ALTER TABLE triples ADD COLUMN graph TEXT DEFAULT 'default'"))

  ;; Migration 2: Add timestamp column
  (with-handlers ([exn:fail? (lambda (e) (void))])
    (query-exec conn "ALTER TABLE triples ADD COLUMN timestamp INTEGER")
    ;; Backfill timestamp for existing records to current time
    (query-exec conn "UPDATE triples SET timestamp = ? WHERE timestamp IS NULL" (current-seconds)))
  conn)

(define (rdf-load! path id) 
  (log-debug 1 'rdf "Loading triples from ~a into graph ~a..." path id)
  (if (file-exists? path)
      (let ([conn (get-db)]
            [lines (file->lines path)]
            [now (current-seconds)])
        (query-exec conn "BEGIN TRANSACTION")
        ;; Clear existing graph content to avoid duplicates if reloading
        (query-exec conn "DELETE FROM triples WHERE graph=?" id)
        (for ([line lines])
          (define parts (string-split line))
          (when (>= (length parts) 3)
            (query-exec conn "INSERT INTO triples (subject, predicate, object, graph, timestamp) VALUES (?, ?, ?, ?, ?)" 
                        (first parts) (second parts) (third parts) id now)))
        (query-exec conn "COMMIT")
        (format "Loaded ~a lines into graph ~a." (length lines) id))
      "File not found."))

(define (rdf-query q id)
  (log-debug 1 'rdf "Query: ~a (context: ~a)" q id)
  (define conn (get-db))
  (define rows
    (cond
      [(string-prefix? (string-upcase q) "SELECT") (query-rows conn q)]
      [(string-contains? q "?") 
       ;; Pattern matching: supports 3 parts (s p o) or 4 parts (s p o g)
       (define parts (string-split q))
       (match parts
         ;; 4-PART PATTERNS (Quads/Hypergraph)
         [(list "?s" p o g) (query-rows conn "SELECT subject, predicate, object, graph, timestamp FROM triples WHERE predicate=? AND object=? AND graph=?" p o g)]
         [(list s "?p" o g) (query-rows conn "SELECT subject, predicate, object, graph, timestamp FROM triples WHERE subject=? AND object=? AND graph=?" s o g)]
         [(list s p "?o" g) (query-rows conn "SELECT subject, predicate, object, graph, timestamp FROM triples WHERE subject=? AND predicate=? AND graph=?" s p g)]
         [(list s p o "?g") (query-rows conn "SELECT subject, predicate, object, graph, timestamp FROM triples WHERE subject=? AND predicate=? AND object=?" s p o)]
         
         ;; 3-PART PATTERNS
         [(list "?s" p o) (query-rows conn "SELECT subject, predicate, object, graph, timestamp FROM triples WHERE predicate=? AND object=?" p o)]
         [(list s "?p" o) (query-rows conn "SELECT subject, predicate, object, graph, timestamp FROM triples WHERE subject=? AND object=?" s o)]
         [(list s p "?o") (query-rows conn "SELECT subject, predicate, object, graph, timestamp FROM triples WHERE subject=? AND predicate=?" s p)]
         
         ;; WILDCARDS
         [(list "?s" "?p" o) (query-rows conn "SELECT subject, predicate, object, graph, timestamp FROM triples WHERE object=?" o)]
         [(list "?s" p "?o") (query-rows conn "SELECT subject, predicate, object, graph, timestamp FROM triples WHERE predicate=?" p)]
         [(list s "?p" "?o") (query-rows conn "SELECT subject, predicate, object, graph, timestamp FROM triples WHERE subject=?" s)]
         
         [_ (query-rows conn "SELECT * FROM triples LIMIT 20")])]
      [else (query-rows conn "SELECT * FROM triples LIMIT 20")]))
  
  (define (row->hash r)
    ;; Convert vector row to hash
    (hash 'result (vector->list r)))
  
  (define res (jsexpr->string (map row->hash rows)))
  (log-debug 2 'rdf "Query Result size: ~a bytes" (string-length res))
  res)

(define (rdf-insert! s p o [g "default"] [ts #f])
  (define timestamp (or ts (current-seconds)))
  (log-debug 1 'rdf "Insert: ~a ~a ~a ~a (@ ~a)" s p o g timestamp)
  (define conn (get-db))
  (query-exec conn "INSERT INTO triples (subject, predicate, object, graph, timestamp) VALUES (?, ?, ?, ?, ?)" s p o g timestamp))