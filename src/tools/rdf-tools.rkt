#lang racket/base
(provide make-rdf-tools execute-rdf-tool)
(require "../stores/rdf-store.rkt" json)

(define (make-rdf-tools)
  (list (hash 'type "function" 
              'function (hash 'name "rdf_load" 
                              'description "Load triples/quads from a file into a named graph."
                              'parameters (hash 'type "object" 
                                                'properties (hash 'path (hash 'type "string" 'description "Path to the file containing triples/quads") 
                                                                  'id (hash 'type "string" 'description "Graph ID/Name to load into"))
                                                'required '("path"))))
        (hash 'type "function" 
              'function (hash 'name "rdf_query" 
                              'description "Query the Knowledge Graph. Returns results with subject, predicate, object, graph, and timestamp."
                              'parameters (hash 'type "object" 
                                                'properties (hash 'query (hash 'type "string" 'description "Query string (e.g. '?s p o ?g')") 
                                                                  'id (hash 'type "string" 'description "Default Graph ID to query (optional)"))
                                                'required '("query"))))
        (hash 'type "function" 
              'function (hash 'name "rdf_insert" 
                              'description "Insert a single triple or quad with an optional timestamp."
                              'parameters (hash 'type "object" 
                                                'properties (hash 'subject (hash 'type "string") 
                                                                  'predicate (hash 'type "string") 
                                                                  'object (hash 'type "string")
                                                                  'graph (hash 'type "string" 'description "Graph Name (optional, defaults to 'default')")
                                                                  'timestamp (hash 'type "integer" 'description "Timestamp (epoch seconds). Defaults to now."))
                                                'required '("subject" "predicate" "object"))))))

(define (execute-rdf-tool name args)
  (case name
    [("rdf_load") (rdf-load! (hash-ref args 'path) (hash-ref args 'id "default"))]
    [("rdf_query") (rdf-query (hash-ref args 'query) (hash-ref args 'id "default"))]
    [("rdf_insert") (rdf-insert! (hash-ref args 'subject) 
                                 (hash-ref args 'predicate) 
                                 (hash-ref args 'object) 
                                 (hash-ref args 'graph "default")
                                 (hash-ref args 'timestamp #f))]
    [else "Unknown"]))