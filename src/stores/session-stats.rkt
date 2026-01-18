#lang racket/base
(provide session-stats-reset! session-stats-add-turn!
         session-stats-get session-stats-display
         session-stats-add-tokens! session-stats-add-cost!
         current-context-limit format-tokens format-cost)
(require racket/format racket/date)

;; Context window limit (configurable per model)
(define current-context-limit (make-parameter 128000))

;; Session statistics
(define session-stats
  (hash 'start-time (current-seconds)
        'turns 0
        'tokens-in 0
        'tokens-out 0
        'total-cost 0.0
        'files-written '()
        'files-read '()
        'tools-used (make-hash)))

;; Reset stats for new session
(define (session-stats-reset!)
  (set! session-stats
        (hash 'start-time (current-seconds)
              'turns 0
              'tokens-in 0
              'tokens-out 0
              'total-cost 0.0
              'files-written '()
              'files-read '()
              'tools-used (make-hash))))

;; Add a turn's worth of stats
(define (session-stats-add-turn! #:tokens-in [tin 0] #:tokens-out [tout 0] #:cost [cost 0.0])
  (set! session-stats
        (hash-set* session-stats
                   'turns (add1 (hash-ref session-stats 'turns))
                   'tokens-in (+ tin (hash-ref session-stats 'tokens-in))
                   'tokens-out (+ tout (hash-ref session-stats 'tokens-out))
                   'total-cost (+ cost (hash-ref session-stats 'total-cost)))))

;; Add tokens (for mid-turn updates)
(define (session-stats-add-tokens! tokens-in tokens-out)
  (set! session-stats
        (hash-set* session-stats
                   'tokens-in (+ tokens-in (hash-ref session-stats 'tokens-in))
                   'tokens-out (+ tokens-out (hash-ref session-stats 'tokens-out)))))

;; Add cost
(define (session-stats-add-cost! cost)
  (set! session-stats
        (hash-set session-stats 'total-cost 
                  (+ cost (hash-ref session-stats 'total-cost)))))

;; Record tool usage
(define (session-stats-record-tool! tool-name)
  (define tools (hash-ref session-stats 'tools-used))
  (hash-set! tools tool-name (add1 (hash-ref tools tool-name 0))))

;; Record file operations
(define (session-stats-record-file! path mode)
  (define key (if (eq? mode 'write) 'files-written 'files-read))
  (define current (hash-ref session-stats key))
  (unless (member path current)
    (set! session-stats (hash-set session-stats key (cons path current)))))

;; Get current stats
(define (session-stats-get)
  (define total-tokens (+ (hash-ref session-stats 'tokens-in)
                          (hash-ref session-stats 'tokens-out)))
  (define context-pct (if (> (current-context-limit) 0)
                          (* 100.0 (/ total-tokens (current-context-limit)))
                          0))
  (hash-set* session-stats
             'total-tokens total-tokens
             'context-percent context-pct
             'context-limit (current-context-limit)
             'elapsed-seconds (- (current-seconds) (hash-ref session-stats 'start-time))))

;; Format token count for display
(define (format-tokens n)
  (cond
    [(>= n 1000000) (format "~aM" (real->decimal-string (/ n 1000000.0) 1))]
    [(>= n 1000) (format "~ak" (real->decimal-string (/ n 1000.0) 1))]
    [else (format "~a" n)]))

;; Format cost for display
(define (format-cost c)
  (cond
    [(< c 0.01) (format "$~a" (real->decimal-string c 4))]
    [(< c 1.0) (format "$~a" (real->decimal-string c 3))]
    [else (format "$~a" (real->decimal-string c 2))]))

;; Context bar visualization
(define (context-bar percent [width 20])
  (define filled (inexact->exact (round (* (/ percent 100.0) width))))
  (define empty (- width filled))
  (define color (cond
                  [(< percent 50) "\033[32m"]   ; green
                  [(< percent 80) "\033[33m"]   ; yellow
                  [else "\033[31m"]))           ; red
  (format "~a~a~a\033[0m ~a%"
          color
          (make-string filled #\█)
          (make-string empty #\░)
          (real->decimal-string percent 1)))

;; Display session stats (for REPL status line)
(define (session-stats-display #:compact? [compact? #f])
  (define stats (session-stats-get))
  (define tin (hash-ref stats 'tokens-in))
  (define tout (hash-ref stats 'tokens-out))
  (define total (hash-ref stats 'total-tokens))
  (define cost (hash-ref stats 'total-cost))
  (define pct (hash-ref stats 'context-percent))
  (define turns (hash-ref stats 'turns))
  
  (if compact?
      ;; Single-line compact format
      (format "T~a │ ~a↓ ~a↑ │ ~a │ ~a"
              turns
              (format-tokens tin)
              (format-tokens tout)
              (format-cost cost)
              (context-bar pct 15))
      ;; Multi-line detailed format
      (string-append
       (format "┌─ Session Stats ─────────────────────────────────────~n")
       (format "│ Turns: ~a   Elapsed: ~as~n" turns (hash-ref stats 'elapsed-seconds))
       (format "│ Tokens: ~a in + ~a out = ~a total~n" 
               (format-tokens tin) (format-tokens tout) (format-tokens total))
       (format "│ Cost: ~a~n" (format-cost cost))
       (format "│ Context: ~a~n" (context-bar pct 30))
       (format "└──────────────────────────────────────────────────────~n"))))
