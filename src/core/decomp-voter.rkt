#lang racket
(provide VotingConfig VotingConfig-n-voters VotingConfig-k-threshold 
         VotingConfig-timeout-ms VotingConfig-decorrelate?
         VoteTally VoteTally-responses VoteTally-counts VoteTally-winner
         VOTING-NONE VOTING-LOW VOTING-MEDIUM VOTING-HIGH VOTING-CRITICAL
         voting-config-for-stakes
         responses-equivalent? normalize-response
         tally-votes first-to-k-winner
         run-voting-round
         make-decorrelated-params
         vote-until-consensus
         estimate-voting-cost)

(require racket/async-channel racket/match racket/string racket/format)

;; ============================================================================
;; VOTING CONFIGURATION
;; ============================================================================

(struct VotingConfig (n-voters k-threshold timeout-ms decorrelate?) #:transparent)

(define VOTING-NONE     (VotingConfig 1 1 30000 #f))
(define VOTING-LOW      (VotingConfig 2 2 45000 #t))
(define VOTING-MEDIUM   (VotingConfig 3 2 60000 #t))
(define VOTING-HIGH     (VotingConfig 5 3 90000 #t))
(define VOTING-CRITICAL (VotingConfig 7 4 120000 #t))

(define (voting-config-for-stakes stakes)
  (match stakes
    ['none     VOTING-NONE]
    ['low      VOTING-LOW]
    ['medium   VOTING-MEDIUM]
    ['high     VOTING-HIGH]
    ['critical VOTING-CRITICAL]
    [_ VOTING-NONE]))

;; ============================================================================
;; RESPONSE EQUIVALENCE
;; ============================================================================

(define (normalize-response response)
  (string-trim
   (string-downcase
    (regexp-replace* #px"\\s+" response " "))))

(define (responses-equivalent? r1 r2 #:mode [mode 'exact])
  (match mode
    ['exact      (string=? r1 r2)]
    ['normalized (string=? (normalize-response r1) (normalize-response r2))]
    ['semantic   (string=? (normalize-response r1) (normalize-response r2))]))

;; ============================================================================
;; VOTE TALLYING
;; ============================================================================

(struct VoteTally (responses counts winner) #:transparent)

(define (first-to-k-winner counts k)
  (for/first ([(response count) (in-hash counts)]
              #:when (>= count k))
    response))

(define (tally-votes responses k-threshold #:mode [mode 'normalized])
  (define counts (make-hash))
  (define unique-responses '())
  
  (for ([r (in-list responses)])
    (define normalized (if (eq? mode 'exact) r (normalize-response r)))
    (define existing-key
      (for/first ([key (in-hash-keys counts)]
                  #:when (responses-equivalent? key normalized #:mode mode))
        key))
    (if existing-key
        (hash-update! counts existing-key add1)
        (begin
          (hash-set! counts normalized 1)
          (set! unique-responses (cons normalized unique-responses)))))
  
  (define winner (first-to-k-winner counts k-threshold))
  (VoteTally (reverse unique-responses) counts winner))

;; ============================================================================
;; DECORRELATION STRATEGIES
;; ============================================================================

(define (make-decorrelated-params base-params voter-index n-voters)
  (define base-temp (hash-ref base-params 'temperature 0.7))
  (define temp-range 0.3)
  (define new-temp (+ base-temp (* (/ voter-index n-voters) temp-range)))
  (define seed (+ (current-milliseconds) (* voter-index 12345)))
  (hash 'temperature (min 1.0 new-temp)
        'seed seed))

;; ============================================================================
;; PARALLEL VOTING EXECUTION
;; ============================================================================

(define (run-voting-round config run-fn task #:api-key api-key #:model model)
  (define n (VotingConfig-n-voters config))
  (define k (VotingConfig-k-threshold config))
  (define timeout (VotingConfig-timeout-ms config))
  (define decorrelate? (VotingConfig-decorrelate? config))
  
  (define result-channel (make-async-channel))
  (define responses '())
  (define responses-lock (make-semaphore 1))
  
  (define threads
    (for/list ([i (in-range n)])
      (thread
       (λ ()
         (with-handlers ([exn:fail? 
                          (λ (e) 
                            (async-channel-put result-channel 
                                               (hash 'index i 'error (exn-message e))))])
           (define params
             (if decorrelate?
                 (make-decorrelated-params (hash) i n)
                 (hash)))
           (define result (run-fn task 
                                  #:api-key api-key 
                                  #:model model
                                  #:temperature (hash-ref params 'temperature 0.7)
                                  #:seed (hash-ref params 'seed #f)))
           (async-channel-put result-channel (hash 'index i 'response result)))))))
  
  (define deadline (+ (current-inexact-milliseconds) timeout))
  (define collected 0)
  (define all-responses '())
  
  (let loop ()
    (define remaining (- deadline (current-inexact-milliseconds)))
    (when (and (< collected n) (> remaining 0))
      (define result 
        (sync/timeout (/ remaining 1000.0) result-channel))
      (when result
        (set! collected (add1 collected))
        (when (hash-has-key? result 'response)
          (set! all-responses (cons (hash-ref result 'response) all-responses)))
        (loop))))
  
  (for ([t (in-list threads)])
    (when (thread-running? t)
      (kill-thread t)))
  
  (define tally (tally-votes all-responses k))
  (values (VoteTally-winner tally) all-responses tally))

;; ============================================================================
;; VOTING WITH RETRIES
;; ============================================================================

(define (vote-until-consensus config run-fn task 
                               #:max-rounds [max-rounds 3]
                               #:api-key api-key 
                               #:model model)
  (define all-responses-across-rounds '())
  
  (let loop ([round 1])
    (define-values (winner responses tally)
      (run-voting-round config run-fn task #:api-key api-key #:model model))
    (set! all-responses-across-rounds 
          (append all-responses-across-rounds responses))
    
    (cond
      [winner 
       (values winner round all-responses-across-rounds)]
      [(>= round max-rounds)
       (define final-tally (tally-votes all-responses-across-rounds 1))
       (define best-response
         (for/fold ([best #f] [best-count 0])
                   ([(resp count) (in-hash (VoteTally-counts final-tally))])
           (if (> count best-count)
               (values resp count)
               (values best best-count))))
       (values best-response round all-responses-across-rounds)]
      [else
       (loop (add1 round))])))

;; ============================================================================
;; COST TRACKING
;; ============================================================================

(define MODEL-COSTS
  (hash "gpt-4" (hash 'input 0.03 'output 0.06)
        "gpt-4-turbo" (hash 'input 0.01 'output 0.03)
        "gpt-4o" (hash 'input 0.005 'output 0.015)
        "gpt-4o-mini" (hash 'input 0.00015 'output 0.0006)
        "claude-3-opus" (hash 'input 0.015 'output 0.075)
        "claude-3-sonnet" (hash 'input 0.003 'output 0.015)
        "claude-3-haiku" (hash 'input 0.00025 'output 0.00125)
        "claude-sonnet-4" (hash 'input 0.003 'output 0.015)))

(define (estimate-voting-cost config model tokens-per-call)
  (define n (VotingConfig-n-voters config))
  (define costs (hash-ref MODEL-COSTS model 
                          (hash 'input 0.01 'output 0.03)))
  (define input-tokens (quotient tokens-per-call 2))
  (define output-tokens (quotient tokens-per-call 2))
  (define cost-per-call 
    (+ (* input-tokens (/ (hash-ref costs 'input) 1000))
       (* output-tokens (/ (hash-ref costs 'output) 1000))))
  (* n cost-per-call))
