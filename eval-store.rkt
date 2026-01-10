#lang racket/base
(provide log-eval! get-profile-stats get-tool-stats suggest-profile evolve-profile!)
(require json racket/file racket/list racket/hash racket/string "debug.rkt")

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
                   #:feedback [feedback ""])
  (make-directory* (build-path (find-system-path 'home-dir) ".agentd"))
  (log-debug 1 'eval "Task ~a: ~a (profile: ~a)" task-id (if success? "SUCCESS" "FAIL") profile)
  
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
                        'feedback feedback) out)
      (newline out))
    #:exists 'append)
  
  ;; Update aggregate stats
  (update-profile-stats! profile success? task-type tools-used))

;; Update running statistics for profile performance
(define (update-profile-stats! profile success? task-type tools-used)
  (define stats (load-profile-stats))
  (define profile-key (if (symbol? profile) (symbol->string profile) profile))
  (define current (hash-ref stats profile-key (hash 'total 0 'success 0 'task_types (hash) 'tool_freq (hash))))
  
  (define new-total (add1 (hash-ref current 'total)))
  (define new-success (+ (hash-ref current 'success) (if success? 1 0)))
  
  ;; Update task type frequency
  (define task-types (hash-ref current 'task_types))
  (define new-task-types (hash-set task-types task-type (add1 (hash-ref task-types task-type 0))))
  
  ;; Update tool usage frequency
  (define tool-freq (hash-ref current 'tool_freq))
  (define new-tool-freq
    (for/fold ([freq tool-freq]) ([tool tools-used])
      (hash-set freq tool (add1 (hash-ref freq tool 0)))))
  
  (define updated (hash-set stats profile-key 
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
      (hash-ref stats (if (symbol? profile) (symbol->string profile) profile) #f)
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
    (define task-types (hash-ref data 'task_types (hash)))
    (when (hash-has-key? task-types task-type)
      (define rate (hash-ref data 'success_rate 0.0))
      (when (> rate best-rate)
        (set! best-profile (string->symbol profile-name))
        (set! best-rate rate))))
  
  (values best-profile best-rate))

;; Evolve a profile by adding frequently successful tools
;; This connects to GEPA's self-optimization philosophy
(define (evolve-profile! profile-name #:threshold [threshold 0.7])
  (define stats (get-profile-stats profile-name))
  (unless stats (error 'evolve-profile! "Unknown profile: ~a" profile-name))
  
  (define success-rate (hash-ref stats 'success_rate 0.0))
  (define tool-freq (hash-ref stats 'tool_freq (hash)))
  
  ;; Get most used tools
  (define sorted-tools 
    (sort (hash->list tool-freq) > #:key cdr))
  
  (define top-tools (take sorted-tools (min 5 (length sorted-tools))))
  
  (hash 'profile profile-name
        'success_rate success-rate
        'recommended_tools (map car top-tools)
        'evaluation (if (>= success-rate threshold) "stable" "needs_improvement")))
