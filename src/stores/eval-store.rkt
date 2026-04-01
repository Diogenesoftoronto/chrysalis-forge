#lang racket/base
(provide log-eval! get-profile-stats get-tool-stats suggest-profile evolve-profile!)
(require json racket/file racket/list racket/hash racket/string "../utils/debug.rkt")

;; ============================================================================
;; EVAL STORE - Track sub-agent performance and learn optimal profiles
;; ============================================================================

(define EVAL-PATH (build-path (find-system-path 'home-dir) ".agentd" "evals.jsonl"))
(define PROFILE-STATS-PATH (build-path (find-system-path 'home-dir) ".agentd" "profile_stats.json"))

;; Log an evaluation result for a sub-agent task
;; success?: did the task complete successfully
;; profile: which tool profile was used
;; task-type: categorization of task (e.g., "file-edit", "search", "vcs")
;; tools-used: list of tool names actually invoked
;; feedback: optional user/system feedback
(define (log-eval! #:task-id task-id 
                   #:success? success? 
                   #:profile profile
                   #:task-type [task-type "unknown"]
                   #:tools-used [tools-used '()]
                   #:duration-ms [duration-ms 0]
                   #:feedback [feedback ""]
                   #:candidate-id [candidate-id #f]
                   #:eval-stage [eval-stage "default"])
  (make-directory* (build-path (find-system-path 'home-dir) ".agentd"))
  (log-debug 1 'eval "Task ~a: ~a (profile: ~a, candidate: ~a, stage: ~a)" 
             task-id (if success? "SUCCESS" "FAIL") profile candidate-id eval-stage)
  
  ;; Append to eval log
  (call-with-output-file EVAL-PATH
    (λ (out) 
      (write-json (hash 'ts (current-seconds)
                        'task_id task-id
                        'success success?
                        'profile (if (symbol? profile) (symbol->string profile) profile)
                        'task_type task-type
                        'tools_used tools-used
                        'duration_ms duration-ms
                        'feedback feedback
                        'candidate_id candidate-id
                        'eval_stage eval-stage) out)
      (newline out))
    #:exists 'append)
  
  ;; Update aggregate stats
  (update-profile-stats! profile success? task-type tools-used))

;; Update running statistics for profile performance
;; Helper: look up a key that may be symbol or string in a hash from read-json
(define (jref h key [default #f])
  (cond
    [(hash-ref h key #f)]
    [(and (symbol? key) (hash-ref h (symbol->string key) #f))]
    [(and (string? key) (hash-ref h (string->symbol key) #f))]
    [else default]))

;; Ensure key is a symbol (write-json requires symbol keys)
(define (->sym k) (if (symbol? k) k (string->symbol k)))

(define (update-profile-stats! profile success? task-type tools-used)
  (define stats (load-profile-stats))
  (define profile-sym (->sym (if (symbol? profile) (symbol->string profile) profile)))
  (define current (jref stats profile-sym (hash 'total 0 'success 0 'task_types (hash) 'tool_freq (hash))))

  (define new-total (add1 (jref current 'total 0)))
  (define new-success (+ (jref current 'success 0) (if success? 1 0)))

  ;; Update task type frequency (symbol keys for JSON)
  (define task-types (jref current 'task_types (hash)))
  (define task-sym (->sym task-type))
  (define new-task-types (hash-set task-types task-sym (add1 (jref task-types task-sym 0))))

  ;; Update tool usage frequency (symbol keys for JSON)
  (define tool-freq (jref current 'tool_freq (hash)))
  (define new-tool-freq
    (for/fold ([freq tool-freq]) ([tool tools-used])
      (define tool-sym (->sym tool))
      (hash-set freq tool-sym (add1 (jref freq tool-sym 0)))))

  (define updated (hash-set stats profile-sym
                            (hash 'total new-total
                                  'success new-success
                                  'success_rate (/ new-success new-total 1.0)
                                  'task_types new-task-types
                                  'tool_freq new-tool-freq)))
  (save-profile-stats! updated))

(define (load-profile-stats)
  (if (file-exists? PROFILE-STATS-PATH)
      (call-with-input-file PROFILE-STATS-PATH read-json)
      (hash)))

(define (save-profile-stats! stats)
  (make-directory* (build-path (find-system-path 'home-dir) ".agentd"))
  (call-with-output-file PROFILE-STATS-PATH
    (λ (out) (write-json stats out))
    #:exists 'replace))

;; Get performance stats for a profile
(define (get-profile-stats [profile #f])
  (define stats (load-profile-stats))
  (if profile
      (jref stats (if (symbol? profile) (symbol->string profile) profile) #f)
      stats))

;; Get tool usage frequency across all evals
(define (get-tool-stats)
  (define stats (load-profile-stats))
  (define all-tool-freq (make-hash))
  (for ([(k v) (in-hash stats)])
    (for ([(tool count) (in-hash (hash-ref v 'tool_freq (hash)))])
      (hash-set! all-tool-freq tool (+ (hash-ref all-tool-freq tool 0) count))))
  all-tool-freq)

;; Suggest best profile for a task type based on historical success
(define (suggest-profile task-type)
  (define stats (load-profile-stats))
  (define best-profile 'all)
  (define best-rate 0.0)
  
  (for ([(profile-name data) (in-hash stats)])
    (define task-types (jref data 'task_types (hash)))
    (when (or (hash-has-key? task-types task-type)
              (hash-has-key? task-types (if (symbol? task-type) (symbol->string task-type) task-type)))
      (define rate (jref data 'success_rate 0.0))
      (when (> rate best-rate)
        (set! best-profile (string->symbol (if (symbol? profile-name) (symbol->string profile-name) profile-name)))
        (set! best-rate rate))))
  
  (values best-profile best-rate))

;; Evolve a profile by adding frequently successful tools
;; This connects to GEPA's self-optimization philosophy
(define (evolve-profile! profile-name #:threshold [threshold 0.7])
  (define stats (get-profile-stats profile-name))
  (unless stats (error 'evolve-profile! "Unknown profile: ~a" profile-name))
  
  (define success-rate (jref stats 'success_rate 0.0))
  (define tool-freq (jref stats 'tool_freq (hash)))
  
  ;; Get most used tools
  (define sorted-tools 
    (sort (hash->list tool-freq) > #:key cdr))
  
  (define top-tools (take sorted-tools (min 5 (length sorted-tools))))
  
  (hash 'profile profile-name
        'success_rate success-rate
        'recommended_tools (map car top-tools)
        'evaluation (if (>= success-rate threshold) "stable" "needs_improvement")))
