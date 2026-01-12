#lang racket

(provide DecompositionPhenotype
         DecompositionPhenotype?
         DecompositionPhenotype-depth
         DecompositionPhenotype-breadth
         DecompositionPhenotype-cost
         DecompositionPhenotype-context
         DecompositionPhenotype-success-rate
         DecompositionPattern
         DecompositionPattern?
         DecompositionPattern-phenotype
         DecompositionPattern-strategy
         DecompositionArchive
         DecompositionArchive?
         DecompositionArchive-point-cloud
         decomp-phenotype-distance
         find-decomp-bounds
         normalize-decomp-phenotype
         PRIORITY-PHENOTYPE-MAP
         priority->target-phenotype
         select-decomposition-pattern
         phenotype->bin-key
         score-decomposition)

(require racket/list racket/string racket/math json)

(struct DecompositionPhenotype (depth breadth cost context success-rate) #:transparent)
(struct DecompositionPattern (phenotype strategy) #:transparent)
(struct DecompositionArchive (point-cloud) #:transparent)

(define (decomp-phenotype-distance p1 p2)
  (sqrt (+ (expt (- (DecompositionPhenotype-depth p1) (DecompositionPhenotype-depth p2)) 2)
           (expt (- (DecompositionPhenotype-breadth p1) (DecompositionPhenotype-breadth p2)) 2)
           (expt (- (DecompositionPhenotype-cost p1) (DecompositionPhenotype-cost p2)) 2)
           (expt (- (DecompositionPhenotype-context p1) (DecompositionPhenotype-context p2)) 2)
           (expt (- (DecompositionPhenotype-success-rate p1) (DecompositionPhenotype-success-rate p2)) 2))))

(define (find-decomp-bounds point-cloud)
  (define phenos (map DecompositionPattern-phenotype point-cloud))
  (define depths (map DecompositionPhenotype-depth phenos))
  (define breadths (map DecompositionPhenotype-breadth phenos))
  (define costs (map DecompositionPhenotype-cost phenos))
  (define contexts (map DecompositionPhenotype-context phenos))
  (define success-rates (map DecompositionPhenotype-success-rate phenos))
  (values (list (apply min depths) (apply min breadths) (apply min costs) 
                (apply min contexts) (apply min success-rates))
          (list (apply max depths) (apply max breadths) (apply max costs)
                (apply max contexts) (apply max success-rates))))

(define (normalize-decomp-phenotype pheno mins maxs)
  (define (safe-norm v lo hi) (if (= lo hi) 0.5 (/ (- v lo) (- hi lo))))
  (DecompositionPhenotype
   (safe-norm (DecompositionPhenotype-depth pheno) (first mins) (first maxs))
   (safe-norm (DecompositionPhenotype-breadth pheno) (second mins) (second maxs))
   (safe-norm (DecompositionPhenotype-cost pheno) (third mins) (third maxs))
   (safe-norm (DecompositionPhenotype-context pheno) (fourth mins) (fourth maxs))
   (safe-norm (DecompositionPhenotype-success-rate pheno) (fifth mins) (fifth maxs))))

(define PRIORITY-PHENOTYPE-MAP
  (hash 'cheap   (DecompositionPhenotype 2 2 0.1 0.2 0.6)
        'fast    (DecompositionPhenotype 2 4 0.3 0.3 0.6)
        'best    (DecompositionPhenotype 4 6 0.7 0.6 0.9)
        'verbose (DecompositionPhenotype 5 8 0.8 0.8 0.85)
        'accurate (DecompositionPhenotype 4 4 0.8 0.5 0.95)))

(define KEYWORD-PRIORITY-MAP
  (hash "cheap" 'cheap "budget" 'cheap "economical" 'cheap
        "fast" 'fast "quick" 'fast "rapid" 'fast
        "best" 'best "optimal" 'best "quality" 'best
        "verbose" 'verbose "detailed" 'verbose "thorough" 'verbose
        "accurate" 'accurate "precise" 'accurate "correct" 'accurate))

(define (priority->target-phenotype priority [send! #f])
  (cond
    [(symbol? priority)
     (hash-ref PRIORITY-PHENOTYPE-MAP priority 
               (lambda () (hash-ref PRIORITY-PHENOTYPE-MAP 'best)))]
    [(string? priority)
     (define lower (string-downcase priority))
     (define matched-key
       (for/first ([(kw sym) (in-hash KEYWORD-PRIORITY-MAP)]
                   #:when (string-contains? lower kw))
         sym))
     (cond
       [matched-key (hash-ref PRIORITY-PHENOTYPE-MAP matched-key)]
       [send!
        (define prompt
          (format "The user wants a decomposition strategy with priority: \"~a\"\n\nReturn JSON with fields (0.0-1.0 scale):\n- depth: how deep should task decomposition go\n- breadth: how many parallel subtasks\n- cost: acceptable token cost\n- context: context richness needed\n- success_rate: minimum acceptable success rate\n\nOutput STRICT JSON only." priority))
        (define-values (ok? raw meta) (send! prompt))
        (if ok?
            (let ([parsed (with-handlers ([exn:fail? (lambda (_) (hash))])
                           (string->jsexpr raw))])
              (DecompositionPhenotype
               (* 5.0 (hash-ref parsed 'depth 0.5))
               (* 8.0 (hash-ref parsed 'breadth 0.5))
               (hash-ref parsed 'cost 0.5)
               (hash-ref parsed 'context 0.5)
               (hash-ref parsed 'success_rate 0.7)))
            (hash-ref PRIORITY-PHENOTYPE-MAP 'best))]
       [else (hash-ref PRIORITY-PHENOTYPE-MAP 'best)])]
    [else (hash-ref PRIORITY-PHENOTYPE-MAP 'best)]))

(define (select-decomposition-pattern archive target-phenotype)
  (define cloud (DecompositionArchive-point-cloud archive))
  (cond
    [(null? cloud) #f]
    [else
     (define-values (mins maxs) (find-decomp-bounds cloud))
     (define target-norm (normalize-decomp-phenotype target-phenotype mins maxs))
     (define scored
       (for/list ([pattern cloud])
         (define pheno (DecompositionPattern-phenotype pattern))
         (define pheno-norm (normalize-decomp-phenotype pheno mins maxs))
         (cons (decomp-phenotype-distance target-norm pheno-norm) pattern)))
     (define sorted (sort scored < #:key car))
     (cdr (first sorted))]))

(define (phenotype->bin-key phenotype)
  (define (depth-bin d) (cond [(< d 2) 1] [(< d 4) 2] [(< d 6) 3] [else 4]))
  (define (breadth-bin b) (cond [(< b 3) '1-2] [(< b 5) '3-4] [(< b 8) '5-7] [else '8+]))
  (define (cost-bin c) (cond [(< c 0.3) 'low] [(< c 0.7) 'med] [else 'high]))
  (define (context-bin ctx) (cond [(< ctx 0.3) 'low] [(< ctx 0.7) 'med] [else 'high]))
  (list (cons 'depth (depth-bin (DecompositionPhenotype-depth phenotype)))
        (cons 'breadth (breadth-bin (DecompositionPhenotype-breadth phenotype)))
        (cons 'cost (cost-bin (DecompositionPhenotype-cost phenotype)))
        (cons 'context (context-bin (DecompositionPhenotype-context phenotype)))))

(define (score-decomposition phenotype success? duration-ms)
  (define success-weight 0.5)
  (define efficiency-weight 0.3)
  (define cost-weight 0.2)
  (define success-score (if success? 1.0 0.0))
  (define efficiency-score (max 0.0 (- 1.0 (/ duration-ms 60000.0))))
  (define cost-score (- 1.0 (DecompositionPhenotype-cost phenotype)))
  (+ (* success-weight success-score)
     (* efficiency-weight efficiency-score)
     (* cost-weight cost-score)))

(module+ test
  (require rackunit)
  
  (define p1 (DecompositionPhenotype 2 4 0.3 0.4 0.7))
  (define p2 (DecompositionPhenotype 4 6 0.5 0.6 0.8))
  
  (check-true (> (decomp-phenotype-distance p1 p2) 0))
  (check-equal? (decomp-phenotype-distance p1 p1) 0.0)
  
  (check-true (DecompositionPhenotype? (priority->target-phenotype 'cheap)))
  (check-true (DecompositionPhenotype? (priority->target-phenotype "fast query")))
  
  (define archive (DecompositionArchive 
                   (list (DecompositionPattern p1 'sequential)
                         (DecompositionPattern p2 'parallel))))
  (define target (DecompositionPhenotype 2 3 0.2 0.3 0.6))
  (define selected (select-decomposition-pattern archive target))
  (check-true (DecompositionPattern? selected))
  
  (define bin (phenotype->bin-key p1))
  (check-equal? (length bin) 4)
  
  (define score (score-decomposition p1 #t 5000))
  (check-true (> score 0)))
