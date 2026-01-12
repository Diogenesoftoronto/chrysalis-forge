#lang racket/base

(require racket/match
         racket/list)

(provide
 ;; Structs
 (struct-out DecompositionPhenotype)
 (struct-out DecompositionLimits)
 (struct-out DecompStep)
 (struct-out DecompositionPattern)
 (struct-out DecompositionCheckpoint)
 (struct-out DecompositionState)
 (struct-out DecompNode)
 
 ;; Phenotype operations
 make-initial-phenotype
 update-phenotype
 phenotype+
 
 ;; Limits constructors
 limits-for-priority
 
 ;; Explosion detection
 detect-explosion
 
 ;; Checkpoint operations
 checkpoint!
 rollback!
 has-checkpoints?
 
 ;; Tree operations
 make-root-node
 add-child!
 node-depth
 count-leaves
 compute-breadth
 mark-node-status!
 prune-node!
 
 ;; State initialization
 make-decomposition-state)

;;; ============================================================
;;; Core Structs
;;; ============================================================

(struct DecompositionPhenotype (depth breadth accumulated-cost context-size success-rate) #:transparent)
(struct DecompositionLimits (max-depth max-breadth max-cost max-context min-success-rate) #:transparent)
(struct DecompStep (op args depth profile) #:transparent)
(struct DecompositionPattern (id task-type priority steps phenotype stats) #:transparent)
(struct DecompositionCheckpoint (tree-snapshot phenotype step-index reason) #:transparent)

(struct DecompositionState (root-task task-type priority tree phenotype limits checkpoints steps-taken meta) 
  #:transparent #:mutable)

(struct DecompNode (id task status children result profile) #:transparent #:mutable)

;;; ============================================================
;;; Phenotype Operations
;;; ============================================================

(define (make-initial-phenotype)
  (DecompositionPhenotype 0 0 0 0 1.0))

(define (update-phenotype pheno
                          #:depth [d #f]
                          #:breadth [b #f]
                          #:cost [c #f]
                          #:context [ctx #f]
                          #:success [sr #f])
  (DecompositionPhenotype
   (or d (DecompositionPhenotype-depth pheno))
   (or b (DecompositionPhenotype-breadth pheno))
   (or c (DecompositionPhenotype-accumulated-cost pheno))
   (or ctx (DecompositionPhenotype-context-size pheno))
   (or sr (DecompositionPhenotype-success-rate pheno))))

(define (phenotype+ p1 p2)
  (DecompositionPhenotype
   (max (DecompositionPhenotype-depth p1) (DecompositionPhenotype-depth p2))
   (max (DecompositionPhenotype-breadth p1) (DecompositionPhenotype-breadth p2))
   (+ (DecompositionPhenotype-accumulated-cost p1) (DecompositionPhenotype-accumulated-cost p2))
   (+ (DecompositionPhenotype-context-size p1) (DecompositionPhenotype-context-size p2))
   (/ (+ (DecompositionPhenotype-success-rate p1) (DecompositionPhenotype-success-rate p2)) 2)))

;;; ============================================================
;;; Limits Constructors
;;; ============================================================

(define (limits-for-priority priority budget context-limit)
  (match priority
    ['critical
     (DecompositionLimits 10 20 (* budget 2.0) (* context-limit 1.5) 0.6)]
    ['high
     (DecompositionLimits 8 15 (* budget 1.5) context-limit 0.7)]
    ['normal
     (DecompositionLimits 6 10 budget (* context-limit 0.8) 0.75)]
    ['low
     (DecompositionLimits 4 6 (* budget 0.5) (* context-limit 0.5) 0.8)]
    [_
     (DecompositionLimits 6 10 budget context-limit 0.75)]))

;;; ============================================================
;;; Explosion Detection
;;; ============================================================

(define (detect-explosion phenotype limits)
  (cond
    [(> (DecompositionPhenotype-depth phenotype)
        (DecompositionLimits-max-depth limits))
     'depth]
    [(> (DecompositionPhenotype-breadth phenotype)
        (DecompositionLimits-max-breadth limits))
     'breadth]
    [(> (DecompositionPhenotype-accumulated-cost phenotype)
        (DecompositionLimits-max-cost limits))
     'cost]
    [(> (DecompositionPhenotype-context-size phenotype)
        (DecompositionLimits-max-context limits))
     'context]
    [(< (DecompositionPhenotype-success-rate phenotype)
        (DecompositionLimits-min-success-rate limits))
     'low-success]
    [else #f]))

;;; ============================================================
;;; Tree Operations
;;; ============================================================

(define node-id-counter 0)

(define (generate-node-id)
  (set! node-id-counter (add1 node-id-counter))
  (string->symbol (format "node-~a" node-id-counter)))

(define (make-root-node task)
  (DecompNode (generate-node-id) task 'pending '() #f #f))

(define (add-child! parent-node child-node)
  (set-DecompNode-children! parent-node
                            (append (DecompNode-children parent-node) (list child-node))))

(define (node-depth node tree)
  (define (find-depth current depth)
    (cond
      [(eq? (DecompNode-id current) (DecompNode-id node)) depth]
      [else
       (for/or ([child (in-list (DecompNode-children current))])
         (find-depth child (add1 depth)))]))
  (find-depth tree 0))

(define (count-leaves tree)
  (if (null? (DecompNode-children tree))
      1
      (for/sum ([child (in-list (DecompNode-children tree))])
        (count-leaves child))))

(define (compute-breadth tree)
  (define (level-sizes node)
    (if (null? (DecompNode-children node))
        '(1)
        (let ([child-levels (map level-sizes (DecompNode-children node))])
          (cons (length (DecompNode-children node))
                (merge-levels child-levels)))))
  (define (merge-levels level-lists)
    (if (andmap null? level-lists)
        '()
        (cons (for/sum ([lst (in-list level-lists)])
                (if (null? lst) 0 (car lst)))
              (merge-levels (map (λ (lst) (if (null? lst) '() (cdr lst))) level-lists)))))
  (apply max 1 (level-sizes tree)))

(define (mark-node-status! node status)
  (set-DecompNode-status! node status))

(define (prune-node! node)
  (set-DecompNode-status! node 'pruned)
  (for ([child (in-list (DecompNode-children node))])
    (prune-node! child)))

;;; ============================================================
;;; Tree Snapshot (for checkpoints)
;;; ============================================================

(define (snapshot-tree tree)
  (DecompNode
   (DecompNode-id tree)
   (DecompNode-task tree)
   (DecompNode-status tree)
   (map snapshot-tree (DecompNode-children tree))
   (DecompNode-result tree)
   (DecompNode-profile tree)))

(define (restore-tree! target source)
  (set-DecompNode-status! target (DecompNode-status source))
  (set-DecompNode-result! target (DecompNode-result source))
  (set-DecompNode-children! target 
                            (for/list ([src-child (in-list (DecompNode-children source))]
                                       [tgt-child (in-list (DecompNode-children target))])
                              (restore-tree! tgt-child src-child)
                              tgt-child)))

;;; ============================================================
;;; Checkpoint Operations
;;; ============================================================

(define (checkpoint! state reason)
  (define snap (snapshot-tree (DecompositionState-tree state)))
  (define cp (DecompositionCheckpoint snap
                                       (DecompositionState-phenotype state)
                                       (DecompositionState-steps-taken state)
                                       reason))
  (set-DecompositionState-checkpoints! state 
                                        (cons cp (DecompositionState-checkpoints state)))
  state)

(define (rollback! state)
  (define cps (DecompositionState-checkpoints state))
  (when (null? cps)
    (error 'rollback! "No checkpoints available"))
  (define cp (car cps))
  (restore-tree! (DecompositionState-tree state) (DecompositionCheckpoint-tree-snapshot cp))
  (set-DecompositionState-phenotype! state (DecompositionCheckpoint-phenotype cp))
  (set-DecompositionState-steps-taken! state (DecompositionCheckpoint-step-index cp))
  (set-DecompositionState-checkpoints! state (cdr cps))
  state)

(define (has-checkpoints? state)
  (not (null? (DecompositionState-checkpoints state))))

;;; ============================================================
;;; State Initialization
;;; ============================================================

(define (make-decomposition-state root-task task-type priority limits)
  (DecompositionState
   root-task
   task-type
   priority
   (make-root-node root-task)
   (make-initial-phenotype)
   limits
   '()
   0
   (hasheq)))
