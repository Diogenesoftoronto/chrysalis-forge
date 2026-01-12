#lang racket/base
(provide (struct-out DecompStep)
         (struct-out DecompositionPattern)
         (struct-out DecompositionPhenotype)
         (struct-out DecompositionArchive)
         ensure-archive-dir!
         load-archive
         save-archive!
         list-archives
         pattern->jsexpr
         jsexpr->pattern
         phenotype->jsexpr
         jsexpr->phenotype
         step->jsexpr
         jsexpr->step
         record-pattern!
         get-pattern-by-id
         prune-archive
         archive-stats)

(require json racket/file racket/list racket/hash racket/string racket/set)

;; ============================================================================
;; DECOMPOSITION ARCHIVE - Persist decomposition patterns for MAP-Elites
;; ============================================================================

;; DecompStep: A single step in a decomposition pattern
(struct DecompStep (id description tool-hints dependencies) #:transparent)

;; DecompositionPattern: A complete decomposition strategy
(struct DecompositionPattern (id name steps metadata) #:transparent)

;; DecompositionPhenotype: Behavioral characteristics of a pattern (for binning)
(struct DecompositionPhenotype (depth parallelism tool-diversity complexity) #:transparent)

;; DecompositionArchive: Archive of patterns for a task type
;; archive: hash of bin-key -> (cons score DecompositionPattern)
;; point-cloud: list of (cons DecompositionPhenotype DecompositionPattern)
(struct DecompositionArchive (task-type archive point-cloud default-id) #:transparent)

;; File paths
(define ARCHIVE-DIR (build-path (find-system-path 'home-dir) ".agentd" "decomp-archives"))
(define ARCHIVE-INDEX-PATH (build-path ARCHIVE-DIR "index.json"))

;; ============================================================================
;; Archive CRUD Operations
;; ============================================================================

(define (ensure-archive-dir!)
  (make-directory* ARCHIVE-DIR))

(define (task-type->filename task-type)
  (string-append (string-replace task-type "/" "_") ".json"))

(define (load-archive task-type)
  (ensure-archive-dir!)
  (define path (build-path ARCHIVE-DIR (task-type->filename task-type)))
  (if (file-exists? path)
      (call-with-input-file path
        (λ (in)
          (define js (read-json in))
          (jsexpr->archive js)))
      (DecompositionArchive task-type (hash) '() #f)))

(define (save-archive! archive)
  (ensure-archive-dir!)
  (define path (build-path ARCHIVE-DIR (task-type->filename (DecompositionArchive-task-type archive))))
  (call-with-output-file path
    (λ (out)
      (write-json (archive->jsexpr archive) out))
    #:exists 'replace)
  (update-archive-index! (DecompositionArchive-task-type archive)))

(define (update-archive-index! task-type)
  (define index (if (file-exists? ARCHIVE-INDEX-PATH)
                    (call-with-input-file ARCHIVE-INDEX-PATH read-json)
                    (hash)))
  (define updated (hash-set index task-type (current-seconds)))
  (call-with-output-file ARCHIVE-INDEX-PATH
    (λ (out) (write-json updated out))
    #:exists 'replace))

(define (list-archives)
  (ensure-archive-dir!)
  (if (file-exists? ARCHIVE-INDEX-PATH)
      (hash-keys (call-with-input-file ARCHIVE-INDEX-PATH read-json))
      '()))

;; ============================================================================
;; Pattern Serialization
;; ============================================================================

(define (step->jsexpr step)
  (hash 'id (DecompStep-id step)
        'description (DecompStep-description step)
        'tool_hints (DecompStep-tool-hints step)
        'dependencies (DecompStep-dependencies step)))

(define (jsexpr->step js)
  (DecompStep (hash-ref js 'id)
              (hash-ref js 'description)
              (hash-ref js 'tool_hints '())
              (hash-ref js 'dependencies '())))

(define (pattern->jsexpr pattern)
  (hash 'id (DecompositionPattern-id pattern)
        'name (DecompositionPattern-name pattern)
        'steps (map step->jsexpr (DecompositionPattern-steps pattern))
        'metadata (DecompositionPattern-metadata pattern)))

(define (jsexpr->pattern js)
  (DecompositionPattern (hash-ref js 'id)
                        (hash-ref js 'name)
                        (map jsexpr->step (hash-ref js 'steps '()))
                        (hash-ref js 'metadata (hash))))

(define (phenotype->jsexpr pheno)
  (hash 'depth (DecompositionPhenotype-depth pheno)
        'parallelism (DecompositionPhenotype-parallelism pheno)
        'tool_diversity (DecompositionPhenotype-tool-diversity pheno)
        'complexity (DecompositionPhenotype-complexity pheno)))

(define (jsexpr->phenotype js)
  (DecompositionPhenotype (hash-ref js 'depth 0)
                          (hash-ref js 'parallelism 0)
                          (hash-ref js 'tool_diversity 0)
                          (hash-ref js 'complexity 0)))

(define (archive->jsexpr archive)
  (hash 'task_type (DecompositionArchive-task-type archive)
        'archive (for/hash ([(k v) (in-hash (DecompositionArchive-archive archive))])
                   (values k (hash 'score (car v)
                                   'pattern (pattern->jsexpr (cdr v)))))
        'point_cloud (for/list ([entry (DecompositionArchive-point-cloud archive)])
                       (hash 'phenotype (phenotype->jsexpr (car entry))
                             'pattern (pattern->jsexpr (cdr entry))))
        'default_id (DecompositionArchive-default-id archive)))

(define (jsexpr->archive js)
  (DecompositionArchive
   (hash-ref js 'task_type)
   (for/hash ([(k v) (in-hash (hash-ref js 'archive (hash)))])
     (values k (cons (hash-ref v 'score)
                     (jsexpr->pattern (hash-ref v 'pattern)))))
   (for/list ([entry (hash-ref js 'point_cloud '())])
     (cons (jsexpr->phenotype (hash-ref entry 'phenotype))
           (jsexpr->pattern (hash-ref entry 'pattern))))
   (hash-ref js 'default_id #f)))

;; ============================================================================
;; Archive Update Operations
;; ============================================================================

(define (phenotype->bin-key pheno)
  (format "d~a_p~a_t~a_c~a"
          (DecompositionPhenotype-depth pheno)
          (DecompositionPhenotype-parallelism pheno)
          (DecompositionPhenotype-tool-diversity pheno)
          (DecompositionPhenotype-complexity pheno)))

(define (compute-phenotype pattern)
  (define steps (DecompositionPattern-steps pattern))
  (define n (length steps))
  (define depth (if (null? steps) 0
                    (add1 (apply max (map (λ (s) (length (DecompStep-dependencies s))) steps)))))
  (define parallelism (if (zero? n) 0
                          (- n (length (remove-duplicates
                                        (append-map DecompStep-dependencies steps))))))
  (define all-tools (append-map DecompStep-tool-hints steps))
  (define tool-diversity (length (remove-duplicates all-tools)))
  (define complexity n)
  (DecompositionPhenotype depth parallelism tool-diversity complexity))

(define (record-pattern! archive pattern score)
  (define pheno (compute-phenotype pattern))
  (define bin-key (phenotype->bin-key pheno))
  (define current-archive (DecompositionArchive-archive archive))
  (define current-cloud (DecompositionArchive-point-cloud archive))
  (define new-cloud (cons (cons pheno pattern) current-cloud))
  (define existing (hash-ref current-archive bin-key #f))
  (define new-archive
    (if (or (not existing) (> score (car existing)))
        (hash-set current-archive bin-key (cons score pattern))
        current-archive))
  (define new-default
    (if (or (not (DecompositionArchive-default-id archive))
            (and existing (> score (car existing))))
        (DecompositionPattern-id pattern)
        (DecompositionArchive-default-id archive)))
  (DecompositionArchive (DecompositionArchive-task-type archive)
                        new-archive
                        new-cloud
                        new-default))

(define (get-pattern-by-id archive pattern-id)
  (or (for/or ([(k v) (in-hash (DecompositionArchive-archive archive))])
        (and (equal? (DecompositionPattern-id (cdr v)) pattern-id)
             (cdr v)))
      (for/or ([entry (DecompositionArchive-point-cloud archive)])
        (and (equal? (DecompositionPattern-id (cdr entry)) pattern-id)
             (cdr entry)))))

(define (prune-archive archive #:max-cloud-size [max-size 1000])
  (define cloud (DecompositionArchive-point-cloud archive))
  (if (<= (length cloud) max-size)
      archive
      (let* ([bins (DecompositionArchive-archive archive)]
             [bin-pattern-ids (for/set ([(k v) (in-hash bins)])
                                (DecompositionPattern-id (cdr v)))]
             [keep-from-bins (filter (λ (entry)
                                       (set-member? bin-pattern-ids
                                                    (DecompositionPattern-id (cdr entry))))
                                     cloud)]
             [others (filter (λ (entry)
                               (not (set-member? bin-pattern-ids
                                                 (DecompositionPattern-id (cdr entry)))))
                             cloud)]
             [remaining-slots (- max-size (length keep-from-bins))]
             [sampled (if (<= (length others) remaining-slots)
                          others
                          (take others remaining-slots))])
        (DecompositionArchive (DecompositionArchive-task-type archive)
                              bins
                              (append keep-from-bins sampled)
                              (DecompositionArchive-default-id archive)))))

;; ============================================================================
;; Archive Statistics
;; ============================================================================

(define (archive-stats archive)
  (define bins (DecompositionArchive-archive archive))
  (define cloud (DecompositionArchive-point-cloud archive))
  (define scores (map car (hash-values bins)))
  (define avg-score (if (null? scores) 0.0 (/ (apply + scores) (length scores))))
  (define best-entry (and (not (null? scores))
                          (argmax car (hash-values bins))))
  (hash 'total-patterns (length cloud)
        'bins-filled (hash-count bins)
        'avg-score avg-score
        'best-pattern-id (and best-entry (DecompositionPattern-id (cdr best-entry)))))
