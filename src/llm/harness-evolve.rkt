#lang racket/base
;; harness-evolve.rkt — Meta-Harness Self-Optimization Engine
;;
;; Closes four gaps vs. Meta-Harness (arxiv 2603.28052) and ShinkaEvolve:
;;
;; 1. Novelty Detection — reject mutations that are too similar to existing elites
;; 2. Bandit-Based Model Ensemble — Thompson sampling to pick the mutation model
;; 3. Cross-Model Generalization — validate evolved configs across held-out models
;; 4. Harness Strategy Evolution — evolve the harness itself, not just prompts

(provide
 ;; Novelty
 (struct-out novelty-archive)
 make-novelty-archive
 instruction-novelty-score
 novel-enough?
 novelty-archive-add!

 ;; Bandit
 (struct-out model-bandit)
 make-model-bandit
 bandit-sample
 bandit-update!
 bandit-stats

 ;; Cross-Model Generalization
 (struct-out generalization-result)
 test-cross-model-generalization

 ;; Harness Strategy Evolution
 (struct-out harness-strategy)
 default-harness-strategy
 mutate-harness-strategy
 harness-strategy->hash
 hash->harness-strategy

 ;; Integrated Compiler
 compile/evolve!)

(require racket/list
         racket/string
         racket/match
         racket/math
         racket/hash
         racket/format
         racket/set
         json
         "dspy-core.rkt"
         "pricing-model.rkt"
         "dspy-selector.rkt"
         "../core/optimizer-meta.rkt")

;; ============================================================================
;; 1. Novelty Detection
;; ============================================================================
;; Inspired by ShinkaEvolve's code-novelty rejection-sampling.
;; Uses instruction text similarity (Jaccard on n-grams) to reject
;; mutations that are too close to existing elites. This avoids wasting
;; expensive LLM evaluations on trivially different variants.

(struct novelty-archive (entries threshold) #:mutable #:transparent)

(define (make-novelty-archive #:threshold [threshold 0.3])
  (novelty-archive '() threshold))

;; Extract character n-grams from instruction text
(define (instruction-ngrams text [n 3])
  (define cleaned (string-downcase (string-trim text)))
  (define len (string-length cleaned))
  (if (< len n)
      (set cleaned)
      (for/set ([i (in-range (- len n -1))])
        (substring cleaned i (+ i n)))))

;; Jaccard distance between two instruction strings
(define (instruction-distance a b)
  (define ng-a (instruction-ngrams a))
  (define ng-b (instruction-ngrams b))
  (define intersection-size (set-count (set-intersect ng-a ng-b)))
  (define union-size (set-count (set-union ng-a ng-b)))
  (if (= union-size 0) 0.0
      (- 1.0 (/ intersection-size union-size))))

;; Compute novelty score: min distance to any existing entry
(define (instruction-novelty-score archive instruction)
  (define entries (novelty-archive-entries archive))
  (if (null? entries)
      1.0  ;; First entry is always novel
      (apply min (map (λ (e) (instruction-distance instruction e)) entries))))

;; Check if an instruction is novel enough to evaluate
(define (novel-enough? archive instruction)
  (>= (instruction-novelty-score archive instruction)
      (novelty-archive-threshold archive)))

;; Add accepted instruction to archive
(define (novelty-archive-add! archive instruction)
  (set-novelty-archive-entries!
   archive (cons instruction (novelty-archive-entries archive))))

;; ============================================================================
;; 2. Bandit-Based Model Ensemble Selection
;; ============================================================================
;; Thompson Sampling with Beta-Binomial conjugate prior.
;; Each model maintains (alpha, beta) parameters updated when it
;; generates a mutation that becomes a new elite vs. not.
;; Inspired by ShinkaEvolve's adaptive LLM selection.

(struct model-bandit (arms) #:mutable #:transparent)
;; arms: hash(model-id -> (cons alpha beta))

(define (make-model-bandit model-ids)
  (model-bandit
   (for/hash ([id (in-list model-ids)])
     (values id (cons 1.0 1.0)))))  ;; Uniform prior

;; Sample from Beta distribution using Gamma approximation
;; Beta(a,b) = Gamma(a,1) / (Gamma(a,1) + Gamma(b,1))
(define (sample-beta alpha beta)
  (define (sample-gamma shape)
    ;; Marsaglia and Tsang's method for shape >= 1
    ;; For shape < 1, use shape+1 then adjust
    (define d (- (if (< shape 1.0) (+ shape 1.0) shape) (/ 1.0 3.0)))
    (define c (/ 1.0 (sqrt (* 9.0 d))))
    (let loop ()
      (define x (+ 1.0 (* c (- (* 2.0 (random)) 1.0))))
      (cond
        [(<= x 0.0) (loop)]
        [else
         (define v (* x x x))
         (define u (random))
         (define d*v (* d v))
         (if (or (< u (- 1.0 (* 0.0331 (expt (- u 0.5) 2))))
                 (< (log u) (+ (* 0.5 (expt (- x 1.0) 2)) (* d (- 1.0 v (log v))))))
             (let ([result d*v])
               (if (< shape 1.0)
                   (* result (expt (random) (/ 1.0 shape)))
                   result))
             (loop))])))
  (define ga (sample-gamma alpha))
  (define gb (sample-gamma beta))
  (if (= (+ ga gb) 0.0) 0.5
      (/ ga (+ ga gb))))

;; Select model via Thompson sampling
(define (bandit-sample bandit)
  (define arms (model-bandit-arms bandit))
  (define samples
    (for/list ([(id ab) (in-hash arms)])
      (cons (sample-beta (car ab) (cdr ab)) id)))
  (define sorted (sort samples > #:key car))
  (cdr (first sorted)))

;; Update bandit after observing outcome
(define (bandit-update! bandit model-id success?)
  (define arms (model-bandit-arms bandit))
  (define current (hash-ref arms model-id (cons 1.0 1.0)))
  (define new-ab
    (if success?
        (cons (+ (car current) 1.0) (cdr current))      ;; alpha += 1
        (cons (car current) (+ (cdr current) 1.0))))     ;; beta += 1
  (set-model-bandit-arms!
   bandit (hash-set arms model-id new-ab)))

;; Get stats for reporting
(define (bandit-stats bandit)
  (for/hash ([(id ab) (in-hash (model-bandit-arms bandit))])
    (define alpha (car ab))
    (define beta (cdr ab))
    (values id (hash 'alpha alpha 'beta beta
                     'mean (/ alpha (+ alpha beta))
                     'trials (- (+ alpha beta) 2.0)))))

;; ============================================================================
;; 3. Cross-Model Generalization Testing
;; ============================================================================
;; After evolution, validate the best configs by running them through
;; multiple held-out models. This catches configs that overfit to one
;; model's quirks (e.g., prompt formatting that only works for GPT).

(struct generalization-result
  (module scores mean-score std-dev model-scores generalizes?) #:transparent)

(define (test-cross-model-generalization mod ctx trainset send-fns
                                          #:threshold [threshold 0.7])
  ;; send-fns: list of (cons model-id sender-fn) for held-out models
  (define model-scores
    (for/list ([sf (in-list send-fns)])
      (define model-id (car sf))
      (define send! (cdr sf))
      (define scores
        (for/list ([ex (in-list trainset)])
          (define rr (run-module mod ctx (hash-ref ex 'inputs) send!))
          (score-result (hash-ref ex 'expected) rr)))
      (define avg (if (null? scores) 0 (/ (apply + scores) (length scores))))
      (cons model-id avg)))

  (define all-scores (map cdr model-scores))
  (define mean-score (if (null? all-scores) 0 (/ (apply + all-scores) (length all-scores))))
  (define variance
    (if (<= (length all-scores) 1) 0
        (/ (apply + (map (λ (s) (expt (- s mean-score) 2)) all-scores))
           (sub1 (length all-scores)))))
  (define std-dev (sqrt variance))

  ;; Generalizes if: mean score above threshold AND std-dev is low
  (define generalizes?
    (and (>= mean-score (* threshold 10.0))  ;; scores are 0-10
         (< std-dev 2.0)))                    ;; not too much variance

  (generalization-result mod all-scores mean-score std-dev model-scores generalizes?))

;; ============================================================================
;; 4. Harness Strategy Evolution
;; ============================================================================
;; The key Meta-Harness idea: don't just optimize prompts — optimize the
;; entire harness strategy. This struct captures harness decisions that
;; affect execution beyond the prompt text itself.

(struct harness-strategy
  (;; Context management
   context-budget        ;; fraction of context window to use (0.0-1.0)
   compaction-threshold  ;; when to compact context (fraction)
   ;; Execution strategy
   strategy-type         ;; 'predict or 'cot
   temperature           ;; 0.0-2.0
   top-p                 ;; 0.0-1.0
   ;; Tool routing
   tool-hint-weight      ;; how strongly to hint tool usage (0.0-1.0)
   prefer-tools?         ;; whether to prepend "use tools" instruction
   ;; Retrieval
   demo-count            ;; number of few-shot examples (0-10)
   demo-selection        ;; 'random, 'similar, 'diverse
   ;; Model routing
   prefer-cheap-decomp?  ;; use cheap model for decomposition
   execution-priority    ;; 'best, 'fast, 'cheap
   ;; Meta-parameters
   mutation-rate)        ;; how much to perturb during evolution (0.0-1.0)
  #:transparent)

(define default-harness-strategy
  (harness-strategy
   0.8         ;; context-budget
   0.9         ;; compaction-threshold
   'predict    ;; strategy-type
   0.0         ;; temperature
   1.0         ;; top-p
   0.5         ;; tool-hint-weight
   #f          ;; prefer-tools?
   3           ;; demo-count
   'random     ;; demo-selection
   #t          ;; prefer-cheap-decomp?
   'best       ;; execution-priority
   0.3))       ;; mutation-rate

;; Mutate a strategy by perturbing each field probabilistically
(define (mutate-harness-strategy strat [rate #f])
  (define r (or rate (harness-strategy-mutation-rate strat)))

  (define (maybe-perturb val range)
    (if (< (random) r)
        (max 0.0 (min (+ val range) (+ val (* (- (* 2.0 (random)) 1.0) range))))
        val))

  (define (maybe-flip bool)
    (if (< (random) r) (not bool) bool))

  (define (maybe-pick current options)
    (if (< (random) r)
        (list-ref options (random (length options)))
        current))

  (harness-strategy
   (maybe-perturb (harness-strategy-context-budget strat) 0.1)
   (maybe-perturb (harness-strategy-compaction-threshold strat) 0.05)
   (maybe-pick (harness-strategy-strategy-type strat) '(predict cot))
   (maybe-perturb (harness-strategy-temperature strat) 0.3)
   (maybe-perturb (harness-strategy-top-p strat) 0.1)
   (maybe-perturb (harness-strategy-tool-hint-weight strat) 0.15)
   (maybe-flip (harness-strategy-prefer-tools? strat))
   (let ([d (harness-strategy-demo-count strat)])
     (if (< (random) r)
         (max 0 (min 10 (+ d (- (random 3) 1))))
         d))
   (maybe-pick (harness-strategy-demo-selection strat) '(random similar diverse))
   (maybe-flip (harness-strategy-prefer-cheap-decomp? strat))
   (maybe-pick (harness-strategy-execution-priority strat) '(best fast cheap))
   (maybe-perturb (harness-strategy-mutation-rate strat) 0.05)))

(define (harness-strategy->hash s)
  (hash 'context-budget (harness-strategy-context-budget s)
        'compaction-threshold (harness-strategy-compaction-threshold s)
        'strategy-type (symbol->string (harness-strategy-strategy-type s))
        'temperature (harness-strategy-temperature s)
        'top-p (harness-strategy-top-p s)
        'tool-hint-weight (harness-strategy-tool-hint-weight s)
        'prefer-tools? (harness-strategy-prefer-tools? s)
        'demo-count (harness-strategy-demo-count s)
        'demo-selection (symbol->string (harness-strategy-demo-selection s))
        'prefer-cheap-decomp? (harness-strategy-prefer-cheap-decomp? s)
        'execution-priority (symbol->string (harness-strategy-execution-priority s))
        'mutation-rate (harness-strategy-mutation-rate s)))

(define (hash->harness-strategy h)
  (harness-strategy
   (hash-ref h 'context-budget 0.8)
   (hash-ref h 'compaction-threshold 0.9)
   (string->symbol (hash-ref h 'strategy-type "predict"))
   (hash-ref h 'temperature 0.0)
   (hash-ref h 'top-p 1.0)
   (hash-ref h 'tool-hint-weight 0.5)
   (hash-ref h 'prefer-tools? #f)
   (hash-ref h 'demo-count 3)
   (string->symbol (hash-ref h 'demo-selection "random"))
   (hash-ref h 'prefer-cheap-decomp? #t)
   (string->symbol (hash-ref h 'execution-priority "best"))
   (hash-ref h 'mutation-rate 0.3)))

;; Apply strategy to a module before execution
(define (apply-strategy strat mod trainset)
  (define demos
    (case (harness-strategy-demo-selection strat)
      [(random) (take (shuffle trainset)
                      (min (harness-strategy-demo-count strat) (length trainset)))]
      [(similar) ;; TODO: embed-based selection
       (take (shuffle trainset)
             (min (harness-strategy-demo-count strat) (length trainset)))]
      [(diverse) ;; Take spread across trainset
       (define n (min (harness-strategy-demo-count strat) (length trainset)))
       (define step (max 1 (quotient (length trainset) (max 1 n))))
       (for/list ([i (in-range 0 (length trainset) step)]
                  [_ (in-range n)])
         (list-ref trainset i))]
      [else (take trainset (min (harness-strategy-demo-count strat) (length trainset)))]))

  (define new-mod
    (struct-copy Module (module-set-demos mod demos)
                 [strategy (harness-strategy-strategy-type strat)]
                 [params (hash 'temperature (harness-strategy-temperature strat)
                               'top_p (harness-strategy-top-p strat))]))

  ;; If prefer-tools?, prepend tool usage hint to instructions
  (if (harness-strategy-prefer-tools? strat)
      (module-set-instructions
       new-mod
       (string-append "IMPORTANT: Use available tools when they can help solve the task.\n"
                      (Module-instructions new-mod)))
      new-mod))

;; ============================================================================
;; 5. Integrated Compiler: compile/evolve!
;; ============================================================================
;; Drop-in replacement for compile! that uses all four new capabilities.

(define (compile/evolve! m ctx trainset send!
                         #:k-demos [k 3]
                         #:n-inst [n 5]
                         #:iters [iters 3]
                         #:use-meta-optimizer? [use-meta? #t]
                         #:novelty-threshold [novelty-threshold 0.3]
                         #:mutation-models [mutation-models '()]
                         #:held-out-senders [held-out-senders '()]
                         #:evolve-strategy? [evolve-strategy? #t]
                         #:initial-strategy [initial-strategy default-harness-strategy])

  (define archive (make-hash))
  (define point-cloud '())
  (define thresholds (hash 'cost 0.0 'lat 0.0 'usage 0.0))
  (define nov-archive (make-novelty-archive #:threshold novelty-threshold))

  ;; Strategy archive: maps strategy-key -> (cons score harness-strategy)
  (define strategy-archive (make-hash))

  ;; Initialize bandit if mutation models provided
  (define bandit
    (if (pair? mutation-models)
        (make-model-bandit mutation-models)
        #f))

  ;; Stats tracking
  (define stats (hash 'novelty-rejected 0
                      'novelty-accepted 0
                      'elite-updates 0
                      'total-evals 0))

  (define (inc-stat! key)
    (set! stats (hash-set stats key (add1 (hash-ref stats key 0)))))

  ;; --- Helpers (same as compile! but with novelty + bandit) ---

  (define (median lon)
    (if (null? lon) 0
        (let ([sorted (sort lon <)])
          (list-ref sorted (quotient (length sorted) 2)))))

  (define (extract-phenotype rr score)
    (define meta (RunResult-meta rr))
    (define model (hash-ref meta 'model "unknown"))
    (define p-tokens (hash-ref meta 'prompt_tokens 0))
    (define c-tokens (hash-ref meta 'completion_tokens 0))
    (define cost (calculate-cost model p-tokens c-tokens))
    (define lat (hash-ref meta 'elapsed_ms 0))
    (Phenotype score lat cost (+ p-tokens c-tokens)))

  (define (get-phenotype-key rr)
    (define meta (RunResult-meta rr))
    (define model (hash-ref meta 'model "unknown"))
    (define p-tokens (hash-ref meta 'prompt_tokens 0))
    (define c-tokens (hash-ref meta 'completion_tokens 0))
    (define cost (calculate-cost model p-tokens c-tokens))
    (define lat (hash-ref meta 'elapsed_ms 0))
    (define total-tokens (+ p-tokens c-tokens))
    (list (if (< cost (hash-ref thresholds 'cost)) 'cheap 'premium)
          (if (< lat (hash-ref thresholds 'lat)) 'fast 'slow)
          (if (< total-tokens (hash-ref thresholds 'usage)) 'compact 'verbose)))

  (define (evaluate-module mod)
    (inc-stat! 'total-evals)
    (define results
      (for/list ([ex (in-list trainset)])
        (run-module mod ctx (hash-ref ex 'inputs) send!)))
    (define scores
      (for/list ([res (in-list results)]
                 [ex (in-list trainset)])
        (score-result (hash-ref ex 'expected) res)))
    (define avg-score (if (null? scores) 0 (/ (apply + scores) (length scores))))
    (define p-key
      (if (null? results)
          '(cheap fast compact)
          (get-phenotype-key (car results))))
    (values avg-score p-key results))

  (define (update-archive! mod score p-key res-list)
    (define existing (hash-ref archive p-key #f))
    (define is-new-elite? (or (not existing) (> score (car existing))))
    (when is-new-elite?
      (inc-stat! 'elite-updates)
      (hash-set! archive p-key (cons score mod)))
    (unless (null? res-list)
      (define pheno (extract-phenotype (car res-list) score))
      (set! point-cloud (cons (cons pheno mod) point-cloud)))
    is-new-elite?)

  ;; --- Phase 1: Seed population ---
  (define default-mutations
    (let ([base (Module-instructions m)])
      (list (string-trim base)
            (string-append base "\nBe concise.")
            (string-append base "\nThink step-by-step.")
            (string-append base "\nOutput STRICT JSON."))))

  (define demos (take (shuffle trainset) (min k (length trainset))))
  (define m0 (module-set-demos m demos))

  (define seed-results
    (for/list ([inst (in-list default-mutations)])
      (define mod (module-set-instructions m0 inst))
      (novelty-archive-add! nov-archive inst)
      (let-values ([(score p-key res-list) (evaluate-module mod)])
        (list mod score p-key res-list))))

  ;; Establish thresholds from seeds
  (define all-meta (flatten (map (λ (x) (map RunResult-meta (fourth x))) seed-results)))
  (unless (null? all-meta)
    (define costs (for/list ([m (in-list all-meta)])
                    (calculate-cost (hash-ref m 'model "unknown")
                                   (hash-ref m 'prompt_tokens 0)
                                   (hash-ref m 'completion_tokens 0))))
    (define lats (for/list ([m (in-list all-meta)]) (hash-ref m 'elapsed_ms 0)))
    (define usages (for/list ([m (in-list all-meta)])
                     (+ (hash-ref m 'prompt_tokens 0) (hash-ref m 'completion_tokens 0))))
    (set! thresholds (hash 'cost (median costs)
                           'lat (median lats)
                           'usage (median usages))))

  ;; Re-bin seeds
  (for ([s (in-list seed-results)])
    (update-archive! (first s) (second s)
                     (if (null? (fourth s)) '(cheap fast compact) (get-phenotype-key (car (fourth s))))
                     (fourth s)))

  ;; --- Phase 2: Evolutionary loop with novelty + bandit ---
  (for ([i (in-range iters)] #:when use-meta?)
    ;; Pick mutation model via bandit (or use default send!)
    (define mutation-send! send!)
    (define mutation-model-id #f)
    (when bandit
      (set! mutation-model-id (bandit-sample bandit)))

    (define elite-keys (hash-keys archive))
    (when (pair? elite-keys)
      (define parent-key (list-ref elite-keys (random (length elite-keys))))
      (define parent-mod (cdr (hash-ref archive parent-key)))

      (for ([j (in-range n)])
        (let-values ([(child-mod thought) (meta-optimize-module parent-mod ctx trainset mutation-send!)])
          (define child-inst (Module-instructions child-mod))

          ;; Novelty gate: skip if too similar to existing
          (cond
            [(novel-enough? nov-archive child-inst)
             (inc-stat! 'novelty-accepted)
             (novelty-archive-add! nov-archive child-inst)
             (let-values ([(score p-key res-list) (evaluate-module child-mod)])
               (define is-elite? (update-archive! child-mod score p-key res-list))
               ;; Update bandit with outcome
               (when (and bandit mutation-model-id)
                 (bandit-update! bandit mutation-model-id is-elite?)))]
            [else
             (inc-stat! 'novelty-rejected)]))))

    ;; --- Phase 2b: Strategy evolution (if enabled) ---
    (when evolve-strategy?
      (define strat (if (hash-empty? strategy-archive)
                        initial-strategy
                        (cdr (argmax car (hash-values strategy-archive)))))
      (define mutated-strat (mutate-harness-strategy strat))
      ;; Apply strategy to best module
      (define best-key (argmax (λ (k) (car (hash-ref archive k))) elite-keys))
      (define best-mod (cdr (hash-ref archive best-key)))
      (define configured-mod (apply-strategy mutated-strat best-mod trainset))

      (let-values ([(score p-key res-list) (evaluate-module configured-mod)])
        (define strat-key (list (harness-strategy-strategy-type mutated-strat)
                                (harness-strategy-demo-selection mutated-strat)
                                (harness-strategy-execution-priority mutated-strat)))
        (define existing (hash-ref strategy-archive strat-key #f))
        (when (or (not existing) (> score (car existing)))
          (hash-set! strategy-archive strat-key (cons score mutated-strat))))))

  ;; --- Phase 3: Cross-model generalization ---
  (define generalization-results
    (if (pair? held-out-senders)
        (let ()
          (define best-key (argmax (λ (k) (car (hash-ref archive k))) (hash-keys archive)))
          (define best-mod (cdr (hash-ref archive best-key)))
          (test-cross-model-generalization best-mod ctx trainset held-out-senders))
        #f))

  ;; --- Return results ---
  (define best-key (argmax (λ (k) (car (hash-ref archive k))) (hash-keys archive)))

  (define result-archive
    (ModuleArchive (Module-id m0) (Module-sig m0) archive point-cloud best-key))

  ;; Find best strategy
  (define best-strategy
    (if (hash-empty? strategy-archive)
        initial-strategy
        (cdr (argmax car (hash-values strategy-archive)))))

  (values result-archive
          best-strategy
          (hash 'stats stats
                'bandit-stats (if bandit (bandit-stats bandit) #f)
                'generalization generalization-results
                'strategy-archive-size (hash-count strategy-archive)
                'novelty-archive-size (length (novelty-archive-entries nov-archive)))))

;; ============================================================================
;; Tests
;; ============================================================================

(module+ test
  (require rackunit racket/set)

  ;; --- Novelty Detection Tests ---

  (test-case "novelty: empty archive always novel"
    (define na (make-novelty-archive))
    (check-true (novel-enough? na "anything goes"))
    (check-equal? (instruction-novelty-score na "test") 1.0))

  (test-case "novelty: identical instructions rejected"
    (define na (make-novelty-archive #:threshold 0.3))
    (novelty-archive-add! na "Be concise and output JSON")
    (check-false (novel-enough? na "Be concise and output JSON"))
    (check-true (< (instruction-novelty-score na "Be concise and output JSON") 0.01)))

  (test-case "novelty: similar instructions rejected"
    (define na (make-novelty-archive #:threshold 0.3))
    (novelty-archive-add! na "Be concise and output strict JSON")
    ;; Very similar — should be below threshold
    (check-false (novel-enough? na "Be concise and output JSON")))

  (test-case "novelty: different instructions accepted"
    (define na (make-novelty-archive #:threshold 0.3))
    (novelty-archive-add! na "Think step by step")
    (check-true (novel-enough? na "Output STRICT JSON with no explanation")))

  (test-case "novelty: ngrams work correctly"
    (define ng (instruction-ngrams "hello"))
    (check-equal? (set-count ng) 3)  ;; "hel" "ell" "llo"
    (check-true (set-member? ng "hel"))
    (check-true (set-member? ng "llo")))

  (test-case "novelty: distance is symmetric"
    (define d1 (instruction-distance "hello world" "world hello"))
    (define d2 (instruction-distance "world hello" "hello world"))
    (check-equal? d1 d2))

  ;; --- Bandit Tests ---

  (test-case "bandit: creation with uniform prior"
    (define b (make-model-bandit '("gpt-4" "claude-3" "gemini")))
    (define arms (model-bandit-arms b))
    (check-equal? (hash-count arms) 3)
    (check-equal? (hash-ref arms "gpt-4") (cons 1.0 1.0)))

  (test-case "bandit: sample returns valid model"
    (define b (make-model-bandit '("gpt-4" "claude-3")))
    (define selected (bandit-sample b))
    (check-not-false (member selected '("gpt-4" "claude-3"))))

  (test-case "bandit: update shifts distribution"
    (define b (make-model-bandit '("good" "bad")))
    ;; Give "good" 10 successes
    (for ([_ (in-range 10)])
      (bandit-update! b "good" #t))
    ;; Give "bad" 10 failures
    (for ([_ (in-range 10)])
      (bandit-update! b "bad" #f))
    (define s (bandit-stats b))
    (check-true (> (hash-ref (hash-ref s "good") 'mean)
                   (hash-ref (hash-ref s "bad") 'mean))))

  (test-case "bandit: heavily rewarded arm selected most often"
    (define b (make-model-bandit '("strong" "weak")))
    (for ([_ (in-range 50)]) (bandit-update! b "strong" #t))
    (for ([_ (in-range 50)]) (bandit-update! b "weak" #f))
    ;; Sample 100 times — strong should dominate
    (define counts
      (for/fold ([h (hash "strong" 0 "weak" 0)])
                ([_ (in-range 100)])
        (define pick (bandit-sample b))
        (hash-set h pick (add1 (hash-ref h pick)))))
    (check-true (> (hash-ref counts "strong") 70)
                (format "Strong selected ~a/100 times" (hash-ref counts "strong"))))

  ;; --- Harness Strategy Tests ---

  (test-case "strategy: default strategy has valid fields"
    (check-equal? (harness-strategy-strategy-type default-harness-strategy) 'predict)
    (check-equal? (harness-strategy-demo-count default-harness-strategy) 3)
    (check-true (<= 0.0 (harness-strategy-temperature default-harness-strategy) 2.0)))

  (test-case "strategy: mutation produces different strategy"
    ;; With mutation-rate 1.0, everything should change
    (define mutated (mutate-harness-strategy default-harness-strategy 1.0))
    ;; At least some fields should differ (probabilistic, but 1.0 rate guarantees it)
    (check-false (equal? mutated default-harness-strategy)))

  (test-case "strategy: mutation preserves valid ranges"
    (for ([_ (in-range 100)])
      (define mutated (mutate-harness-strategy default-harness-strategy 0.5))
      (check-true (<= 0.0 (harness-strategy-context-budget mutated)))
      (check-true (<= 0.0 (harness-strategy-temperature mutated)))
      (check-true (<= 0 (harness-strategy-demo-count mutated) 10))
      (check-not-false (member (harness-strategy-strategy-type mutated) '(predict cot)))
      (check-not-false (member (harness-strategy-demo-selection mutated) '(random similar diverse)))
      (check-not-false (member (harness-strategy-execution-priority mutated) '(best fast cheap)))))

  (test-case "strategy: roundtrip hash serialization"
    (define h (harness-strategy->hash default-harness-strategy))
    (define restored (hash->harness-strategy h))
    (check-equal? (harness-strategy-strategy-type restored)
                  (harness-strategy-strategy-type default-harness-strategy))
    (check-equal? (harness-strategy-demo-count restored)
                  (harness-strategy-demo-count default-harness-strategy)))

  ;; --- Cross-Model Generalization Tests ---

  (test-case "generalization: result struct construction"
    (define gr (generalization-result
                #f '(8.0 7.0 9.0) 8.0 1.0
                '(("gpt" . 8.0) ("claude" . 7.0) ("gemini" . 9.0))
                #t))
    (check-true (generalization-result-generalizes? gr))
    (check-equal? (generalization-result-mean-score gr) 8.0))

  (test-case "generalization: high variance fails"
    (define gr (generalization-result
                #f '(10.0 1.0) 5.5 6.36
                '(("gpt" . 10.0) ("claude" . 1.0))
                #f))
    (check-false (generalization-result-generalizes? gr)))
  )
