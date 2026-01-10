#lang racket/base
(provide gepa-evolve! gepa-meta-evolve!)
(require "../stores/context-store.rkt" "../llm/openai-client.rkt" json racket/file "../llm/dspy-core.rkt" "../llm/pricing-model.rkt" "../utils/debug.rkt")

(define META-PATH (build-path (find-system-path 'home-dir) ".agentd" "meta_prompt.txt"))

(define (get-meta) (if (file-exists? META-PATH) (file->string META-PATH) "You are an Optimizer. Rewrite the System Prompt to fix feedback. Return JSON {new_system_prompt}."))

(define (log-cost-analysis model usage)
  (define in-tok (hash-ref usage 'prompt_tokens 0))
  (define out-tok (hash-ref usage 'completion_tokens 0))
  (define cost (calculate-cost model in-tok out-tok))
  (log-debug 1 'optimizer "Optimizer Step Cost: $~a (~a in / ~a out)" (real->decimal-string cost 4) in-tok out-tok))

(define (check-usage!)
  (define stats (fetch-usage-stats))
  (when stats
    (define costs (hash-ref stats 'costs #f))
    (when costs
      (define results (hash-ref costs 'results '()))
      (when (not (null? results))
        (define amount (hash-ref (first results) 'amount (hash)))
        (log-debug 1 'optimizer "Current Daily Usage: $~a" (hash-ref amount 'value 0))))))

(define (gepa-evolve! feedback [model "gpt-5.2"])
  (check-usage!)
  (define active (ctx-get-active))
  (define sender (make-openai-sender #:model model))
  (define-values (ok? res usage) (sender (format "~a\nCURRENT: ~a\nFEEDBACK: ~a" (get-meta) (Ctx-system active) feedback)))
  (if ok?
      (let ([new-sys (hash-ref (string->jsexpr res) 'new_system_prompt)])
        (log-cost-analysis model usage)
        (save-ctx! (let ([db (load-ctx)]) (hash-set db 'items (hash-set (hash-ref db 'items) (format "evo_~a" (current-seconds)) (struct-copy Ctx active [system new-sys])))))
        "Context Evolved.")
      "Evolution Failed."))

(define (gepa-meta-evolve! feedback [model "gpt-5.2"])
  (check-usage!)
  (define sender (make-openai-sender #:model model))
  (define-values (ok? res usage) (sender (format "Rewrite this optimizer prompt:\n~a\nFeedback: ~a\nReturn JSON {new_meta_prompt}" (get-meta) feedback)))
  (if ok? 
      (begin 
        (log-cost-analysis model usage)
        (display-to-file (hash-ref (string->jsexpr res) 'new_meta_prompt) META-PATH #:exists 'replace) 
        "Meta-Optimizer Evolved.") 
      "Failed."))