#lang racket/base
(provide acp-serve acp-notify!)
(require json racket/match racket/port)

(define (acp-notify! out method params)
  (write-json (hash 'jsonrpc "2.0" 'method method 'params params) out) (newline out) (flush-output out))

(define (acp-serve #:modes supported-modes #:on-new-session on-new-session #:run-turn run-turn)
  (define in (current-input-port)) (define out (current-output-port))
  (let loop ()
    (define line (read-line in))
    (unless (eof-object? line)
      (define msg (string->jsexpr line))
      (match (hash-ref msg 'method #f)
        ["initialize" (write-json (hash 'jsonrpc "2.0" 'id (hash-ref msg 'id) 'result (hash 'capabilities (hash 'modes supported-modes))) out) (newline out) (flush-output out)]
        ["session/new" (on-new-session (format "s~a" (random 1000)) (hash-ref (hash-ref msg 'params) 'mode "ask")) (write-json (hash 'jsonrpc "2.0" 'id (hash-ref msg 'id) 'result (hash 'sessionId "s1")) out) (newline out) (flush-output out)]
        ["session/prompt" (run-turn (hash-ref (hash-ref msg 'params) 'sessionId) (hash-ref (hash-ref msg 'params) 'prompt) (λ (t) (acp-notify! out "session/update" (hash 'type "agent_message_chunk" 'content (hash 'type "text" 'text t)))) (λ (_) (void)) (λ () #f))]
        [else (void)])
      (loop))))