#lang racket/base
(provide make-rdf-tools execute-rdf-tool)
(require "rdf-store.rkt" json)

(define (make-rdf-tools)
  (list (hash 'type "function" 'function (hash 'name "rdf_load" 'parameters (hash 'type "object" 'properties (hash 'path (hash 'type "string") 'id (hash 'type "string")))))
        (hash 'type "function" 'function (hash 'name "rdf_query" 'parameters (hash 'type "object" 'properties (hash 'query (hash 'type "string") 'id (hash 'type "string")))))))

(define (execute-rdf-tool name args)
  (case name
    [("rdf_load") (rdf-load! (hash-ref args 'path) (hash-ref args 'id "default"))]
    [("rdf_query") (rdf-query (hash-ref args 'query) (hash-ref args 'id "default"))]
    [else "Unknown"]))