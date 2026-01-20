#lang racket/base
;; Visual Session Summary for CLI
;; Provides sparkline charts, bar charts, and color-coded cost breakdowns.

(require racket/string
         racket/list
         racket/format
         racket/math
         "terminal-style.rkt"
         "message-boxes.rkt")

(provide render-session-summary
         sparkline
         bar-chart
         cost-breakdown)

;; ---------------------------------------------------------------------------
;; Sparkline Charts
;; ---------------------------------------------------------------------------

(define SPARK-CHARS '("▁" "▂" "▃" "▄" "▅" "▆" "▇" "█"))

(define (sparkline data #:width [width 20])
  (cond
    [(null? data) ""]
    [(= (length data) 1) (list-ref SPARK-CHARS 4)]
    [else
     (define min-val (apply min data))
     (define max-val (apply max data))
     (define range (- max-val min-val))
     (define num-chars (length SPARK-CHARS))
     
     ;; Resample data to fit width if needed
     (define resampled
       (if (<= (length data) width)
           data
           (for/list ([i (in-range width)])
             (define idx (exact-floor (* i (/ (length data) width))))
             (list-ref data (min idx (sub1 (length data)))))))
     
     (apply string-append
            (for/list ([val (in-list resampled)])
              (define normalized
                (if (zero? range)
                    0.5
                    (/ (- val min-val) range)))
              (define char-idx (min (sub1 num-chars)
                                    (exact-floor (* normalized num-chars))))
              (list-ref SPARK-CHARS char-idx)))]))

;; ---------------------------------------------------------------------------
;; Horizontal Bar Charts
;; ---------------------------------------------------------------------------

(define BAR-FILLED "█")
(define BAR-EMPTY "░")

(define (bar-chart items #:width [width 40])
  (cond
    [(null? items) ""]
    [else
     (define max-val (apply max (map cdr items)))
     (define max-label-len (apply max (map (λ (p) (string-length (car p))) items)))
     (define bar-width (- width max-label-len 3)) ; 3 for " : " separator area
     
     (string-join
      (for/list ([item (in-list items)])
        (define label (car item))
        (define value (cdr item))
        (define ratio (if (zero? max-val) 0 (/ value max-val)))
        (define filled-len (exact-round (* ratio bar-width)))
        (define empty-len (- bar-width filled-len))
        (define padded-label (~a label #:min-width max-label-len #:align 'right))
        (format "~a ~a~a ~a"
                padded-label
                (make-string filled-len (string-ref BAR-FILLED 0))
                (make-string empty-len (string-ref BAR-EMPTY 0))
                value))
      "\n")]))

;; ---------------------------------------------------------------------------
;; Cost Breakdown
;; ---------------------------------------------------------------------------

(define COST-COLORS
  (hasheq 'input    'cyan
          'output   'magenta
          'total    'yellow
          'cache    'green
          'default  'white))

(define (cost-breakdown costs)
  (define total (for/sum ([v (in-hash-values costs)]) v))
  (define max-cat-len (apply max (cons 1 (map (λ (k) (string-length (symbol->string k)))
                                               (hash-keys costs)))))
  
  (string-join
   (for/list ([cat (in-list (sort (hash-keys costs) symbol<?))])
     (define amount (hash-ref costs cat 0))
     (define pct (if (zero? total) 0 (* 100 (/ amount total))))
     (define col (hash-ref COST-COLORS cat (hash-ref COST-COLORS 'default)))
     (define cat-str (~a (symbol->string cat) #:min-width max-cat-len #:align 'right))
     (styled (format "~a: $~a (~a%)" cat-str (~r amount #:precision '(= 4)) (~r pct #:precision '(= 1)))
             #:fg col))
   "\n"))

;; ---------------------------------------------------------------------------
;; Session Summary Rendering
;; ---------------------------------------------------------------------------

(define (format-duration seconds)
  (cond
    [(< seconds 60) (format "~as" (~r seconds #:precision '(= 1)))]
    [(< seconds 3600) (format "~am ~as"
                              (quotient (exact-floor seconds) 60)
                              (modulo (exact-floor seconds) 60))]
    [else (format "~ah ~am"
                  (quotient (exact-floor seconds) 3600)
                  (quotient (modulo (exact-floor seconds) 3600) 60))]))

(define (format-tokens n)
  (cond
    [(< n 1000) (format "~a" n)]
    [(< n 1000000) (format "~aK" (~r (/ n 1000) #:precision '(= 1)))]
    [else (format "~aM" (~r (/ n 1000000) #:precision '(= 2)))]))

(define (render-session-summary stats)
  (define session-id (hash-ref stats 'session-id "unknown"))
  (define model (hash-ref stats 'model "unknown"))
  (define total-cost (hash-ref stats 'total-cost 0))
  (define total-tokens (hash-ref stats 'total-tokens 0))
  (define input-tokens (hash-ref stats 'input-tokens 0))
  (define output-tokens (hash-ref stats 'output-tokens 0))
  (define duration (hash-ref stats 'duration-seconds 0))
  (define tool-usage (hash-ref stats 'tool-usage (hasheq)))
  (define token-history (hash-ref stats 'token-history '()))
  
  (define width (min 70 (terminal-width)))
  (define inner-width (- width 4))
  
  ;; Build content lines
  (define header-line
    (styled (format "Session: ~a" session-id) #:fg 'cyan #:bold? #t))
  
  (define model-line
    (format "Model: ~a" (styled model #:fg 'magenta)))
  
  (define duration-line
    (format "Duration: ~a" (styled (format-duration duration) #:fg 'yellow)))
  
  (define cost-line
    (format "Total Cost: ~a"
            (styled (format "$~a" (~r total-cost #:precision '(= 4)))
                    #:fg 'green #:bold? #t)))
  
  ;; Token summary with sparkline
  (define token-summary
    (format "Tokens: ~a total (~a in / ~a out)"
            (styled (format-tokens total-tokens) #:fg 'cyan)
            (styled (format-tokens input-tokens) #:fg 'blue)
            (styled (format-tokens output-tokens) #:fg 'magenta)))
  
  (define spark-line
    (if (null? token-history)
        ""
        (format "Token trend: ~a"
                (styled (sparkline token-history #:width (min 30 inner-width)) #:fg 'cyan))))
  
  ;; Tool usage bar chart
  (define tool-section
    (if (hash-empty? tool-usage)
        ""
        (let* ([items (sort (for/list ([(k v) (in-hash tool-usage)])
                              (cons (symbol->string k) v))
                            > #:key cdr)]
               [top-items (take items (min 5 (length items)))])
          (string-append
           (styled "Tool Usage:" #:fg 'yellow #:bold? #t)
           "\n"
           (bar-chart top-items #:width (min 45 inner-width))))))
  
  ;; Cost breakdown
  (define cost-section
    (let ([costs (hasheq 'input (* input-tokens 0.000001)
                         'output (* output-tokens 0.000003))])
      (if (zero? total-cost)
          ""
          (string-append
           (styled "Cost Breakdown:" #:fg 'yellow #:bold? #t)
           "\n"
           (cost-breakdown costs)))))
  
  ;; Combine all sections
  (define content
    (string-join
     (filter (λ (s) (not (string=? s "")))
             (list header-line
                   model-line
                   duration-line
                   cost-line
                   ""
                   token-summary
                   spark-line
                   ""
                   tool-section
                   ""
                   cost-section))
     "\n"))
  
  ;; Render in a box
  (message-box content
               #:title "Session Summary"
               #:color 'cyan
               #:width width
               #:icon "📊"))

;; ---------------------------------------------------------------------------
;; Tests
;; ---------------------------------------------------------------------------

(module+ test
  (require rackunit)
  
  ;; Test sparkline
  (check-equal? (sparkline '()) "")
  (check-equal? (string-length (sparkline '(1 2 3 4 5) #:width 5)) 5)
  (check-equal? (sparkline '(1) #:width 5) "▅")
  
  ;; Test bar chart
  (check-true (string-contains? (bar-chart '(("a" . 10) ("b" . 5))) "a"))
  (check-true (string-contains? (bar-chart '(("test" . 100))) "100"))
  
  ;; Test cost breakdown
  (define costs (hasheq 'input 0.01 'output 0.02))
  (check-true (string-contains? (cost-breakdown costs) "input"))
  (check-true (string-contains? (cost-breakdown costs) "output"))
  
  ;; Test format helpers
  (check-equal? (format-duration 30) "30.0s")
  (check-equal? (format-duration 90) "1m 30s")
  (check-equal? (format-duration 3700) "1h 1m")
  (check-equal? (format-tokens 500) "500")
  (check-equal? (format-tokens 1500) "1.5K")
  (check-equal? (format-tokens 1500000) "1.50M"))
