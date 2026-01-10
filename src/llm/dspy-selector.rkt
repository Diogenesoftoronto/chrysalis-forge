#lang racket
(provide select-elite text->vector phenotype-distance normalize-phenotype)
(require "dspy-core.rkt" "openai-client.rkt" json racket/list racket/string racket/math)

;; Euclidean distance between two Phenotypes (normalized)
(define (phenotype-distance p1 p2)
  (sqrt (+ (expt (- (Phenotype-accuracy p1) (Phenotype-accuracy p2)) 2)
           (expt (- (Phenotype-latency p1) (Phenotype-latency p2)) 2)
           (expt (- (Phenotype-cost p1) (Phenotype-cost p2)) 2)
           (expt (- (Phenotype-usage p1) (Phenotype-usage p2)) 2))))

;; Normalize a point cloud to [0,1] range for fair distance comparison
(define (normalize-phenotype pheno mins maxs)
  (define (safe-norm v lo hi) (if (= lo hi) 0.5 (/ (- v lo) (- hi lo))))
  (Phenotype (safe-norm (Phenotype-accuracy pheno) (first mins) (first maxs))
             (safe-norm (Phenotype-latency pheno) (second mins) (second maxs))
             (safe-norm (Phenotype-cost pheno) (third mins) (third maxs))
             (safe-norm (Phenotype-usage pheno) (fourth mins) (fourth maxs))))

;; Find min/max across all phenotypes in point cloud
(define (find-bounds point-cloud)
  (define phenos (map car point-cloud))
  (define accs (map Phenotype-accuracy phenos))
  (define lats (map Phenotype-latency phenos))
  (define costs (map Phenotype-cost phenos))
  (define usages (map Phenotype-usage phenos))
  (values (list (apply min accs) (apply min lats) (apply min costs) (apply min usages))
          (list (apply max accs) (apply max lats) (apply max costs) (apply max usages))))

;; Select the elite closest to target vector using KNN (k=1)
(define (select-elite archive target)
  (define cloud (ModuleArchive-point-cloud archive))
  (when (null? cloud)
    (error "Cannot select elite: point cloud is empty"))
  
  (define-values (mins maxs) (find-bounds cloud))
  (define target-norm (normalize-phenotype target mins maxs))
  
  (define scored
    (for/list ([entry cloud])
      (define pheno (car entry))
      (define mod (cdr entry))
      (define pheno-norm (normalize-phenotype pheno mins maxs))
      (cons (phenotype-distance target-norm pheno-norm) mod)))
  
  (define sorted (sort scored < #:key car))
  (cdr (first sorted)))

;; Keyword-based fast mapping (no LLM call)
(define KEYWORD-MAP
  (hash "fast" (Phenotype 5.0 0.0 0.5 0.5)   ;; Prioritize low latency
        "quick" (Phenotype 5.0 0.0 0.5 0.5)
        "cheap" (Phenotype 5.0 0.5 0.0 0.5)  ;; Prioritize low cost  
        "budget" (Phenotype 5.0 0.5 0.0 0.5)
        "accurate" (Phenotype 10.0 0.5 0.5 0.5) ;; Prioritize accuracy
        "precise" (Phenotype 10.0 0.5 0.5 0.5)
        "best" (Phenotype 10.0 0.5 0.5 0.5)
        "concise" (Phenotype 5.0 0.5 0.5 0.0)   ;; Prioritize low usage
        "compact" (Phenotype 5.0 0.5 0.5 0.0)
        "verbose" (Phenotype 5.0 0.5 0.5 1.0)   ;; High usage acceptable
        "thorough" (Phenotype 10.0 0.8 0.8 1.0)))

;; Convert natural language priority to a target Phenotype
;; Uses keyword matching first, falls back to LLM if no match
(define (text->vector text [send! #f])
  (define lower (string-downcase text))
  
  ;; Check for keyword matches
  (define matched
    (for/first ([(kw pheno) (in-hash KEYWORD-MAP)]
                #:when (string-contains? lower kw))
      pheno))
  
  (cond
    [matched matched]
    [send!
     ;; Use LLM to interpret the request
     (define prompt 
       (format "The user wants an agent with this priority: \"~a\"\n\nReturn a JSON object with these fields (0.0 to 1.0 scale):\n- accuracy: how important is correctness\n- speed: how important is low latency  \n- cost: how important is low token cost\n- brevity: how important is concise output\n\nOutput STRICT JSON only." text))
     (define-values (ok? raw meta) (send! prompt))
     (if ok?
         (let ([parsed (string->jsexpr raw)])
           (Phenotype (* 10.0 (hash-ref parsed 'accuracy 0.5))
                      (- 1.0 (hash-ref parsed 'speed 0.5))     ;; Invert: high speed = low latency
                      (- 1.0 (hash-ref parsed 'cost 0.5))      ;; Invert: low cost priority = low cost value
                      (- 1.0 (hash-ref parsed 'brevity 0.5)))) ;; Invert: brevity = low usage
         (Phenotype 5.0 0.5 0.5 0.5))] ;; Fallback to neutral
    [else (Phenotype 5.0 0.5 0.5 0.5)])) ;; No send! provided, return neutral
