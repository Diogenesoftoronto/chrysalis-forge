#lang racket/base
(provide log-trace!)
(require json racket/file racket/date "debug.rkt")

(define TRACE-PATH (build-path (find-system-path 'home-dir) ".agentd" "traces.jsonl"))

(define (log-trace! #:task task #:history history #:tool-results tool-results #:final-response final #:tokens [tokens (hash)] #:cost [cost 0.0])
  (log-debug 1 'trace "Task: ~a | Cost: $~a" task (real->decimal-string cost 4))
  (make-directory* (build-path (find-system-path 'home-dir) ".agentd"))
  (call-with-output-file TRACE-PATH
    (λ (out) (write-json (hash 'ts (current-seconds) 'task task 'final final 'tokens tokens 'cost cost) out) (newline out))
    #:exists 'append))