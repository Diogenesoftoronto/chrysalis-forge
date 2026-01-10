#lang racket/base

(provide make-acp-tools)
(require json)
(define (make-acp-tools) (list (hash 'type "function" 'function (hash 'name "read_file" 'parameters (hash 'type "object" 'properties (hash 'path (hash 'type "string"))))) (hash 'type "function" 'function (hash 'name "write_file" 'parameters (hash 'type "object" 'properties (hash 'path (hash 'type "string") 'content (hash 'type "string")))))))