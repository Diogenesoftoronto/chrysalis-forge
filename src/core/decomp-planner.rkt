#lang racket/base

(require "geometric-decomposition.rkt"
         (prefix-in sel: "decomp-selector.rkt")
         "decomp-voter.rkt"
         "sub-agent.rkt"
         (prefix-in arch: "../stores/decomp-archive.rkt")
         "../utils/red-flag.rkt"
         "../llm/openai-client.rkt"
         "../stores/eval-store.rkt"
         "../utils/debug.rkt"
         racket/async-channel
         racket/match
         racket/list
         racket/string
         json)

(provide classify-task
         build-limits-from-context
         decompose-task-llm
         suggest-profile-for-subtask
         replay-pattern
         maximal-decomposition
         execute-leaves
         run-geometric-decomposition
         should-vote?
         execute-with-voting
         log-decomposition-progress
         TASK-TYPE-KEYWORDS)

;;; ============================================================
;;; Task Classification
;;; ============================================================

(define TASK-TYPE-KEYWORDS
  (hash "refactor" '("refactor" "restructure" "reorganize" "clean up")
        "implement" '("implement" "create" "build" "add" "write")
        "debug" '("debug" "fix" "bug" "error" "issue" "broken")
        "research" '("find" "search" "look" "analyze" "understand" "explain")
        "test" '("test" "verify" "check" "validate")
        "document" '("document" "docs" "readme" "comment")))

(define (classify-task task-description)
  (define lower-desc (string-downcase task-description))
  (or (for/or ([(task-type keywords) (in-hash TASK-TYPE-KEYWORDS)])
        (and (for/or ([kw (in-list keywords)])
               (string-contains? lower-desc kw))
             task-type))
      "general"))

;;; ============================================================
;;; Limits from Context
;;; ============================================================

(define (extract-priority-from-ctx ctx)
  (cond
    [(hash? ctx) (hash-ref ctx 'priority 'normal)]
    [else 'normal]))

(define (build-limits-from-context ctx budget context-limit)
  (define priority (extract-priority-from-ctx ctx))
  (limits-for-priority priority budget context-limit))

;;; ============================================================
;;; LLM-based Decomposition
;;; ============================================================

(define (decompose-task-llm task send! #:max-subtasks [max-subtasks 4])
  (define prompt
    (format "Decompose this task into smaller, actionable subtasks (max ~a subtasks).
Task: ~a

Return JSON with a 'subtasks' array. Each subtask should have:
- 'description': clear task description
- 'dependencies': list of subtask indices this depends on (0-indexed)
- 'profile_hint': suggested agent profile ('editor', 'researcher', 'vcs', or 'all')

Example:
{\"subtasks\": [
  {\"description\": \"Read the file\", \"dependencies\": [], \"profile_hint\": \"researcher\"},
  {\"description\": \"Make changes\", \"dependencies\": [0], \"profile_hint\": \"editor\"}
]}

Output STRICT JSON only." max-subtasks task))
  
  (define-values (ok? raw meta) (send! prompt))
  
  (if (not ok?)
      (begin
        (log-debug 1 'decomp "LLM decomposition failed: ~a" raw)
        '())
      (let ([flags (red-flag-response raw (make-json-format-config))])
        (define critical (get-critical-flags flags))
        (cond
          [(not (null? critical))
           (log-debug 1 'decomp "LLM response flagged: ~a" (map RedFlag-message critical))
           '()]
          [else
           (with-handlers ([exn:fail? 
                           (λ (e) 
                             (log-debug 1 'decomp "Failed to parse subtasks: ~a" (exn-message e))
                             '())])
             (define parsed (string->jsexpr (string-trim raw)))
             (define subtasks (hash-ref parsed 'subtasks '()))
             (for/list ([st (in-list subtasks)]
                        [i (in-naturals)]
                        #:when (< i max-subtasks))
               st))]))))

(define (suggest-profile-for-subtask subtask-description)
  (define lower-desc (string-downcase subtask-description))
  (cond
    [(or (string-contains? lower-desc "read")
         (string-contains? lower-desc "search")
         (string-contains? lower-desc "find")
         (string-contains? lower-desc "analyze")
         (string-contains? lower-desc "understand"))
     'researcher]
    [(or (string-contains? lower-desc "write")
         (string-contains? lower-desc "create")
         (string-contains? lower-desc "modify")
         (string-contains? lower-desc "edit")
         (string-contains? lower-desc "update")
         (string-contains? lower-desc "patch"))
     'editor]
    [(or (string-contains? lower-desc "commit")
         (string-contains? lower-desc "git")
         (string-contains? lower-desc "jj")
         (string-contains? lower-desc "branch")
         (string-contains? lower-desc "merge"))
     'vcs]
    [else 'all]))

;;; ============================================================
;;; Pattern Replay
;;; ============================================================

(define (adapt-step-to-context step current-task)
  (hash 'id (arch:DecompStep-id step)
        'description (arch:DecompStep-description step)
        'tool_hints (arch:DecompStep-tool-hints step)
        'dependencies (arch:DecompStep-dependencies step)
        'context current-task))

(define (replay-pattern state pattern send! run-subtask!)
  (define steps (arch:DecompositionPattern-steps pattern))
  (define limits (DecompositionState-limits state))
  (define root-task (DecompositionState-root-task state))
  
  (let loop ([remaining-steps steps]
             [step-count 0]
             [current-state state])
    (cond
      [(null? remaining-steps)
       (values current-state step-count #t)]
      [else
       (define step (car remaining-steps))
       (define adapted (adapt-step-to-context step root-task))
       
       (checkpoint! current-state (format "before-step-~a" (arch:DecompStep-id step)))
       
       (define step-node (make-root-node (arch:DecompStep-description step)))
       (set-DecompNode-profile! step-node 
                                 (or (for/or ([hint (arch:DecompStep-tool-hints step)])
                                       (and (member hint '("editor" "researcher" "vcs"))
                                            (string->symbol hint)))
                                     'all))
       
       (add-child! (DecompositionState-tree current-state) step-node)
       
       (define new-phenotype
         (update-phenotype (DecompositionState-phenotype current-state)
                           #:depth (add1 (DecompositionPhenotype-depth 
                                          (DecompositionState-phenotype current-state)))
                           #:breadth (compute-breadth (DecompositionState-tree current-state))))
       (set-DecompositionState-phenotype! current-state new-phenotype)
       
       (define explosion (detect-explosion new-phenotype limits))
       (cond
         [explosion
          (log-debug 1 'decomp "Explosion detected during replay: ~a" explosion)
          (rollback! current-state)
          (values current-state step-count #f)]
         [else
          (set-DecompositionState-steps-taken! current-state (add1 (DecompositionState-steps-taken current-state)))
          (loop (cdr remaining-steps) (add1 step-count) current-state)])])))

;;; ============================================================
;;; Maximal Decomposition (MAKER-style fallback)
;;; ============================================================

(define (find-pending-leaves node)
  (cond
    [(and (null? (DecompNode-children node))
          (eq? (DecompNode-status node) 'pending))
     (list node)]
    [else
     (append-map find-pending-leaves (DecompNode-children node))]))

(define (can-decompose-further? node max-depth current-depth)
  (and (eq? (DecompNode-status node) 'pending)
       (null? (DecompNode-children node))
       (< current-depth max-depth)))

(define (maximal-decomposition state send! run-subtask!)
  (define limits (DecompositionState-limits state))
  (define max-depth (DecompositionLimits-max-depth limits))
  (define max-iterations 50)
  
  (let loop ([current-state state]
             [iteration 0])
    (cond
      [(>= iteration max-iterations)
       (log-debug 1 'decomp "Max iterations reached in maximal decomposition")
       (values current-state iteration)]
      [else
       (define pending-leaves (find-pending-leaves (DecompositionState-tree current-state)))
       
       (cond
         [(null? pending-leaves)
          (log-debug 2 'decomp "No more pending leaves")
          (values current-state iteration)]
         [else
          (define leaf (car pending-leaves))
          (define current-depth (node-depth leaf (DecompositionState-tree current-state)))
          
          (cond
            [(>= current-depth max-depth)
             (log-debug 2 'decomp "Leaf at max depth, skipping decomposition")
             (loop current-state (add1 iteration))]
            [else
             (checkpoint! current-state (format "before-decompose-~a" (DecompNode-id leaf)))
             
             (define subtasks (decompose-task-llm (DecompNode-task leaf) send! #:max-subtasks 4))
             
             (cond
               [(null? subtasks)
                (log-debug 2 'decomp "No subtasks generated for leaf")
                (loop current-state (add1 iteration))]
               [else
                (for ([st (in-list subtasks)])
                  (define desc (hash-ref st 'description (DecompNode-task leaf)))
                  (define profile-hint (hash-ref st 'profile_hint "all"))
                  (define child (make-root-node desc))
                  (set-DecompNode-profile! child (string->symbol profile-hint))
                  (add-child! leaf child))
                
                (define new-phenotype
                  (update-phenotype (DecompositionState-phenotype current-state)
                                    #:depth (max (DecompositionPhenotype-depth 
                                                  (DecompositionState-phenotype current-state))
                                                 (add1 current-depth))
                                    #:breadth (compute-breadth (DecompositionState-tree current-state))))
                (set-DecompositionState-phenotype! current-state new-phenotype)
                
                (define explosion (detect-explosion new-phenotype limits))
                
                (cond
                  [explosion
                   (log-debug 1 'decomp "Explosion in maximal decomposition: ~a" explosion)
                   (rollback! current-state)
                   (prune-node! leaf)
                   (mark-node-status! leaf 'inline)
                   (loop current-state (add1 iteration))]
                  [else
                   (mark-node-status! leaf 'decomposed)
                   (set-DecompositionState-steps-taken! current-state 
                                                        (add1 (DecompositionState-steps-taken current-state)))
                   (loop current-state (add1 iteration))])])])])])))

;;; ============================================================
;;; Leaf Execution
;;; ============================================================

(define (collect-executable-leaves node)
  (cond
    [(and (null? (DecompNode-children node))
          (member (DecompNode-status node) '(pending inline)))
     (list node)]
    [(eq? (DecompNode-status node) 'pruned)
     '()]
    [else
     (append-map collect-executable-leaves (DecompNode-children node))]))

(define (execute-leaves state run-subtask!)
  (define tree (DecompositionState-tree state))
  (define leaves (collect-executable-leaves tree))
  (define results '())
  
  (log-debug 1 'decomp "Executing ~a leaf tasks" (length leaves))
  
  (for ([leaf (in-list leaves)])
    (define task (DecompNode-task leaf))
    (define profile (or (DecompNode-profile leaf) 'all))
    
    (log-debug 2 'decomp "Executing leaf: ~a (profile: ~a)" 
               (if (> (string-length task) 50)
                   (string-append (substring task 0 50) "...")
                   task)
               profile)
    
    (define start-time (current-inexact-milliseconds))
    
    (with-handlers ([exn:fail? 
                     (λ (e)
                       (mark-node-status! leaf 'failed)
                       (set-DecompNode-result! leaf (exn-message e))
                       (log-eval! #:task-id (symbol->string (DecompNode-id leaf))
                                  #:success? #f
                                  #:profile profile
                                  #:task-type (DecompositionState-task-type state)
                                  #:duration-ms (inexact->exact 
                                                 (round (- (current-inexact-milliseconds) start-time))))
                       (set! results (cons (cons leaf #f) results)))])
      (define result (run-subtask! task profile))
      (define duration (inexact->exact (round (- (current-inexact-milliseconds) start-time))))
      
      (mark-node-status! leaf 'completed)
      (set-DecompNode-result! leaf result)
      
      (log-eval! #:task-id (symbol->string (DecompNode-id leaf))
                 #:success? #t
                 #:profile profile
                 #:task-type (DecompositionState-task-type state)
                 #:duration-ms duration)
      
      (set! results (cons (cons leaf #t) results))))
  
  (define success-count (length (filter cdr results)))
  (define total-count (length results))
  (define success-rate (if (zero? total-count) 1.0 (/ success-count total-count)))
  
  (define new-phenotype
    (update-phenotype (DecompositionState-phenotype state)
                      #:success success-rate))
  (set-DecompositionState-phenotype! state new-phenotype)
  
  state)

;;; ============================================================
;;; Voting Integration
;;; ============================================================

(define (should-vote? step phenotype)
  (define tool-hints (if (arch:DecompStep? step) (arch:DecompStep-tool-hints step) '()))
  (define success-rate (DecompositionPhenotype-success-rate phenotype))
  
  (or (for/or ([hint (in-list tool-hints)])
        (member hint '("write_file" "patch_file" "git_commit" "delete")))
      (< success-rate 0.6)
      (and (hash? step) (hash-ref step 'high_stakes #f))))

(define (execute-with-voting step state send! run-subtask! voting-config)
  (define task (if (arch:DecompStep? step) 
                   (arch:DecompStep-description step)
                   (hash-ref step 'description "")))
  (define profile (if (arch:DecompStep? step)
                      (or (for/or ([h (arch:DecompStep-tool-hints step)])
                            (and (member h '("editor" "researcher" "vcs"))
                                 (string->symbol h)))
                          'all)
                      'all))
  
  (define n-voters (VotingConfig-n-voters voting-config))
  (define k-threshold (VotingConfig-k-threshold voting-config))
  
  (define result-channel (make-async-channel))
  (define responses '())
  
  (for ([i (in-range n-voters)])
    (thread
     (λ ()
       (with-handlers ([exn:fail? 
                        (λ (e) (async-channel-put result-channel (cons 'error (exn-message e))))])
         (define result (run-subtask! task profile))
         (async-channel-put result-channel (cons 'ok result))))))
  
  (define timeout-ms (VotingConfig-timeout-ms voting-config))
  (define deadline (+ (current-inexact-milliseconds) timeout-ms))
  (define collected 0)
  
  (let loop ()
    (define remaining (- deadline (current-inexact-milliseconds)))
    (when (and (< collected n-voters) (> remaining 0))
      (define result (sync/timeout (/ remaining 1000.0) result-channel))
      (when result
        (set! collected (add1 collected))
        (when (eq? (car result) 'ok)
          (set! responses (cons (cdr result) responses)))
        (loop))))
  
  (define winner (if (>= (length responses) k-threshold)
                     (car responses)
                     #f))
  
  (values winner n-voters))

;;; ============================================================
;;; Progress Tracking
;;; ============================================================

(define (log-decomposition-progress state step-name)
  (define phenotype (DecompositionState-phenotype state))
  (log-debug 1 'decomp "Step: ~a | Depth: ~a | Breadth: ~a | Cost: ~a | Success: ~a"
             step-name
             (DecompositionPhenotype-depth phenotype)
             (DecompositionPhenotype-breadth phenotype)
             (DecompositionPhenotype-accumulated-cost phenotype)
             (DecompositionPhenotype-success-rate phenotype)))

;;; ============================================================
;;; Main Entry Point
;;; ============================================================

(define (build-pattern-from-state state)
  (define tree (DecompositionState-tree state))
  (define steps '())
  
  (define (collect-steps node parent-ids)
    (define step (arch:DecompStep (symbol->string (DecompNode-id node))
                                  (DecompNode-task node)
                                  (if (DecompNode-profile node)
                                      (list (symbol->string (DecompNode-profile node)))
                                      '())
                                  parent-ids))
    (set! steps (cons step steps))
    (for ([child (in-list (DecompNode-children node))])
      (collect-steps child (list (symbol->string (DecompNode-id node))))))
  
  (collect-steps tree '())
  
  (arch:DecompositionPattern (format "pattern-~a" (current-seconds))
                             (DecompositionState-task-type state)
                             (reverse steps)
                             (hash 'generated_at (current-seconds)
                                   'priority (DecompositionState-priority state))))

(define (run-geometric-decomposition root-task ctx send! run-subtask!
                                     #:budget [budget 1.0]
                                     #:context-limit [context-limit 80000])
  (log-section "Geometric Decomposition")
  (log-debug 1 'decomp "Starting decomposition for: ~a" 
             (if (> (string-length root-task) 80)
                 (string-append (substring root-task 0 80) "...")
                 root-task))
  
  (define task-type (classify-task root-task))
  (log-debug 1 'decomp "Classified task type: ~a" task-type)
  
  (define priority (extract-priority-from-ctx ctx))
  (define limits (build-limits-from-context ctx budget context-limit))
  (log-debug 2 'decomp "Limits: depth=~a breadth=~a cost=~a"
             (DecompositionLimits-max-depth limits)
             (DecompositionLimits-max-breadth limits)
             (DecompositionLimits-max-cost limits))
  
  (define state (make-decomposition-state root-task task-type priority limits))
  
  (define archive (arch:load-archive task-type))
  (log-debug 2 'decomp "Loaded archive for ~a: ~a patterns" 
             task-type 
             (length (arch:DecompositionArchive-point-cloud archive)))
  
  (define target-phenotype (sel:priority->target-phenotype priority))
  
  (define selected-pattern
    (let ([cloud (arch:DecompositionArchive-point-cloud archive)])
      (and (not (null? cloud))
           (let* ([first-entry (car cloud)]
                  [pattern (cdr first-entry)])
             (and (not (null? (arch:DecompositionPattern-steps pattern)))
                  pattern)))))
  
  (define-values (final-state steps-used success?)
    (cond
      [selected-pattern
       (log-debug 1 'decomp "Replaying pattern: ~a" (arch:DecompositionPattern-id selected-pattern))
       (replay-pattern state selected-pattern send! run-subtask!)]
      [else
       (log-debug 1 'decomp "No pattern found, using maximal decomposition")
       (define-values (s steps) (maximal-decomposition state send! run-subtask!))
       (values s steps #t)]))
  
  (log-decomposition-progress final-state "decomposition-complete")
  
  (define executed-state (execute-leaves final-state run-subtask!))
  
  (define final-phenotype (DecompositionState-phenotype executed-state))
  (define final-success-rate (DecompositionPhenotype-success-rate final-phenotype))
  (define overall-success? (and success? (>= final-success-rate 0.5)))
  
  (when overall-success?
    (define new-pattern (build-pattern-from-state executed-state))
    (define score (if (>= final-success-rate 0.8) 1.0 final-success-rate))
    (define updated-archive (arch:record-pattern! archive new-pattern score))
    (arch:save-archive! updated-archive)
    (log-debug 1 'decomp "Recorded successful pattern: ~a" (arch:DecompositionPattern-id new-pattern)))
  
  (define tree (DecompositionState-tree executed-state))
  (define all-results
    (let collect ([node tree])
      (if (null? (DecompNode-children node))
          (list (cons (DecompNode-task node) (DecompNode-result node)))
          (append-map collect (DecompNode-children node)))))
  
  (log-debug 1 'decomp "Decomposition complete. Success: ~a, Results: ~a" 
             overall-success? 
             (length all-results))
  
  (values all-results final-phenotype overall-success?))

(module+ test
  (require rackunit)
  
  (check-equal? (classify-task "refactor the code") "refactor")
  (check-equal? (classify-task "implement a new feature") "implement")
  (check-equal? (classify-task "debug this error") "debug")
  (check-equal? (classify-task "find the config file") "research")
  (check-equal? (classify-task "do something random") "general")
  
  (check-equal? (suggest-profile-for-subtask "read the file") 'researcher)
  (check-equal? (suggest-profile-for-subtask "write to disk") 'editor)
  (check-equal? (suggest-profile-for-subtask "commit changes") 'vcs)
  (check-equal? (suggest-profile-for-subtask "do something") 'all))
