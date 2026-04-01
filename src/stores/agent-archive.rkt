#lang racket/base
(provide (struct-out AgentVariant)
         (struct-out AgentArchive)
         ensure-agent-archive-dir!
         load-agent-archive
         save-agent-archive!
         record-variant!
         get-variant-by-id
         get-variants-by-parent
         get-best-variants
         variant->jsexpr
         jsexpr->variant)

(require json racket/file racket/list racket/string)

;; ============================================================================
;; AGENT ARCHIVE - Persist agent/workflow variants for evolutionary search
;; ============================================================================

;; AgentVariant: A specific version of an agent component
;; id: Unique identifier
;; parent_id: ID of the parent variant (for lineage)
;; type: 'prompt, 'workflow, 'profile, 'config
;; content: The actual data (string or jsexpr)
;; eval_summary: Hash of metrics (success_rate, avg_duration, cost, etc.)
;; task_family: Primary task type this variant is optimized for
;; metadata: Additional info (timestamp, author, etc.)
;; viable: Boolean gate for parent selection
(struct AgentVariant (id parent-id type content eval-summary task-family metadata viable) #:transparent)

;; AgentArchive: Collection of variants
(struct AgentArchive (variants) #:transparent)

;; File paths
(define ARCHIVE-DIR (build-path (find-system-path 'home-dir) ".agentd" "agent-archives"))

(define (ensure-agent-archive-dir!)
  (make-directory* ARCHIVE-DIR))

(define (type->filename type)
  (string-append (symbol->string type) "_archive.json"))

(define (load-agent-archive type)
  (ensure-agent-archive-dir!)
  (define path (build-path ARCHIVE-DIR (type->filename type)))
  (if (file-exists? path)
      (call-with-input-file path
        (λ (in)
          (define js (read-json in))
          (AgentArchive (map jsexpr->variant (hash-ref js 'variants '())))))
      (AgentArchive '())))

(define (save-agent-archive! type archive)
  (ensure-agent-archive-dir!)
  (define path (build-path ARCHIVE-DIR (type->filename type)))
  (call-with-output-file path
    (λ (out)
      (write-json (hash 'variants (map variant->jsexpr (AgentArchive-variants archive))) out))
    #:exists 'replace))

;; ============================================================================
;; Serialization
;; ============================================================================

(define (variant->jsexpr v)
  (hash 'id (AgentVariant-id v)
        'parent_id (AgentVariant-parent-id v)
        'type (symbol->string (AgentVariant-type v))
        'content (AgentVariant-content v)
        'eval_summary (AgentVariant-eval-summary v)
        'task_family (AgentVariant-task-family v)
        'metadata (AgentVariant-metadata v)
        'viable (AgentVariant-viable v)))

(define (jsexpr->variant js)
  (AgentVariant (hash-ref js 'id)
                (hash-ref js 'parent_id #f)
                (string->symbol (hash-ref js 'type))
                (hash-ref js 'content)
                (hash-ref js 'eval_summary (hash))
                (hash-ref js 'task_family "general")
                (hash-ref js 'metadata (hash))
                (hash-ref js 'viable #t)))

;; ============================================================================
;; Archive Operations
;; ============================================================================

(define (record-variant! archive variant)
  (AgentArchive (cons variant (AgentArchive-variants archive))))

(define (get-variant-by-id archive id)
  (findf (λ (v) (equal? (AgentVariant-id v) id))
         (AgentArchive-variants archive)))

(define (get-variants-by-parent archive parent-id)
  (filter (λ (v) (equal? (AgentVariant-parent-id v) parent-id))
          (AgentArchive-variants archive)))

(define (get-best-variants archive task-family #:limit [limit 5])
  (define family-variants 
    (filter (λ (v) (and (equal? (AgentVariant-task-family v) task-family)
                        (AgentVariant-viable v)))
            (AgentArchive-variants archive)))
  (take (sort family-variants > 
              #:key (λ (v) (hash-ref (AgentVariant-eval-summary v) 'success_rate 0.0)))
        (min limit (length family-variants))))
