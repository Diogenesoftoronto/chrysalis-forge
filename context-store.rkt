#lang racket/base
(provide (all-defined-out))
(provide session-create! session-switch! session-list session-delete!)
(require json racket/file racket/date "dspy-core.rkt")

(define DB-PATH (build-path (find-system-path 'home-dir) ".agentd" "context.json"))

(define (json->ctx j)
  (Ctx (hash-ref j 'system) (hash-ref j 'memory) (hash-ref j 'tool_hints) (string->symbol (hash-ref j 'mode "ask"))))

(define (ctx->json c)
  (hash 'system (Ctx-system c) 'memory (Ctx-memory c) 'tool_hints (Ctx-tool-hints c) 'mode (symbol->string (Ctx-mode c))))

(define (load-ctx)
  (if (file-exists? DB-PATH)
      (let ([db (call-with-input-file DB-PATH (λ (in) (read-json in)))])
        (hash 'active (string->symbol (hash-ref db 'active))
              'items (for/hash ([(k v) (hash-ref db 'items)]) (values k (json->ctx v)))))
      (hash 'active 'default 'items (hash 'default (Ctx (default-system-prompt) "" "" 'ask)))))

(define (default-system-prompt)
  (format #<<EOF
You are agentd, an AI agent. Your task is to analyze content and assist the user.

<rules>
1. Be concise and direct in your responses
2. Focus only on the information requested in the user's prompt
3. If the content is provided in a file path, use the grep and view tools to efficiently search through it
4. When relevant, quote specific sections from the content to support your answer
5. If the requested information is not found, clearly state that
6. Any file paths you use MUST be absolute
7. **IMPORTANT**: If you need information from a linked page or search result, use the web_fetch tool to get that content
8. **IMPORTANT**: If you need to search for more information, use the web_search tool
9. After fetching a link, analyze the content yourself to extract what's needed
10. Don't hesitate to follow multiple links or perform multiple searches if necessary to get complete information
11. **CRITICAL**: At the end of your response, include a "Sources" section listing ALL URLs that were useful in answering the question
</rules>

<env>
Working directory: ~a
Platform: ~a
Today's date: ~a
</env>
EOF
          (current-directory)
          (system-type 'os)
          (parameterize ([date-display-format 'iso-8601]) (date->string (current-date)))))

(define (save-ctx! db)
  (make-directory* (build-path (find-system-path 'home-dir) ".agentd"))
  (let ([json-db (hash 'active (symbol->string (hash-ref db 'active))
                       'items (for/hash ([(k v) (hash-ref db 'items)]) (values k (ctx->json v))))])
    (call-with-output-file DB-PATH (λ (out) (write-json json-db out)) #:exists 'truncate/replace)))

(define (ctx-get-active)
  (define db (load-ctx))
  (hash-ref (hash-ref db 'items) (hash-ref db 'active)))

(define (session-list)
  (define db (load-ctx))
  (values (hash-keys (hash-ref db 'items)) (hash-ref db 'active)))

(define (session-create! name [mode 'code])
  (define db (load-ctx))
  (define items (hash-ref db 'items))
  (if (hash-has-key? items (string->symbol name))
      (error "Session already exists")
      (save-ctx! (hash-set db 'items (hash-set items (string->symbol name) (Ctx (default-system-prompt) "" "" mode))))))

(define (session-switch! name)
  (define db (load-ctx))
  (define items (hash-ref db 'items))
  (if (hash-has-key? items (string->symbol name))
      (save-ctx! (hash-set db 'active (string->symbol name)))
      (error "Session not found")))

(define (session-delete! name)
  (define db (load-ctx))
  (define items (hash-ref db 'items))
  (define sym (string->symbol name))
  (if (equal? sym (hash-ref db 'active))
      (error "Cannot delete active session")
      (if (hash-has-key? items sym)
          (save-ctx! (hash-set db 'items (hash-remove items sym)))
          (error "Session not found"))))