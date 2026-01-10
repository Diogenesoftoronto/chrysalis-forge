#lang racket/base
(provide gepa-evolve! gepa-meta-evolve!)
(require "context-store.rkt" "openai-client.rkt" json racket/file "dspy-core.rkt")

(define META-PATH (build-path (find-system-path 'home-dir) ".agentd" "meta_prompt.txt"))

(define (get-meta) (if (file-exists? META-PATH) (file->string META-PATH) "You are an Optimizer. Rewrite the System Prompt to fix feedback. Return JSON {new_system_prompt}."))

(define (gepa-evolve! feedback [model "gpt-5.2"])
  (define active (ctx-get-active))
  (define sender (make-openai-sender #:model model))
  (define-values (ok? res _) (sender (format "~a\nCURRENT: ~a\nFEEDBACK: ~a" (get-meta) (Ctx-system active) feedback)))
  (if ok?
      (let ([new-sys (hash-ref (string->jsexpr res) 'new_system_prompt)])
        (save-ctx! (let ([db (load-ctx)]) (hash-set db 'items (hash-set (hash-ref db 'items) (format "evo_~a" (current-seconds)) (struct-copy Ctx active [system new-sys])))))
        "Context Evolved.")
      "Evolution Failed."))

(define (gepa-meta-evolve! feedback [model "gpt-5.2"])
  (define sender (make-openai-sender #:model model))
  (define-values (ok? res _) (sender (format "Rewrite this optimizer prompt:\n~a\nFeedback: ~a\nReturn JSON {new_meta_prompt}" (get-meta) feedback)))
  (if ok? (begin (display-to-file (hash-ref (string->jsexpr res) 'new_meta_prompt) META-PATH #:exists 'replace) "Meta-Optimizer Evolved.") "Failed."))