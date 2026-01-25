#lang racket/base
(provide strip-ansi
         text-width
         char-width
         text-height
         wrap-text
         truncate-text
         pad-right
         pad-left
         pad-center
         split-lines
         max-line-width
         visible-slice)

(require racket/string
         racket/list
         racket/match)

;; ============================================================================
;; ANSI Escape Sequence Handling
;; ============================================================================

(define ansi-escape-rx
  (pregexp "\033(?:[@-Z\\\\-_]|\\[[0-?]*[ -/]*[@-~])"))

(define (strip-ansi str)
  (regexp-replace* ansi-escape-rx str ""))

;; ============================================================================
;; Character Width (wcwidth-style)
;; ============================================================================

(define (char-width c)
  (define cp (char->integer c))
  (cond
    [(< cp #x20) 0]
    [(= cp #x7f) 0]
    [(<= #x0300 cp #x036f) 0]
    [(<= #x0483 cp #x0489) 0]
    [(<= #x0591 cp #x05bd) 0]
    [(<= #x1ab0 cp #x1aff) 0]
    [(<= #x1dc0 cp #x1dff) 0]
    [(<= #x20d0 cp #x20ff) 0]
    [(<= #xfe00 cp #xfe0f) 0]
    [(<= #xfe20 cp #xfe2f) 0]
    [(<= #x1100 cp #x115f) 2]
    [(<= #x2e80 cp #x9fff) 2]
    [(<= #xac00 cp #xd7a3) 2]
    [(<= #xf900 cp #xfaff) 2]
    [(<= #xfe10 cp #xfe1f) 2]
    [(<= #xfe30 cp #xfe6f) 2]
    [(<= #xff00 cp #xff60) 2]
    [(<= #xffe0 cp #xffe6) 2]
    [(<= #x20000 cp #x2fffd) 2]
    [(<= #x30000 cp #x3fffd) 2]
    [(<= #x1f300 cp #x1f9ff) 2]
    [(<= #x1f600 cp #x1f64f) 2]
    [(<= #x1f680 cp #x1f6ff) 2]
    [(<= #x1f1e0 cp #x1f1ff) 2]
    [else 1]))

;; ============================================================================
;; Text Width Calculation
;; ============================================================================

(define (text-width str)
  (define cleaned (strip-ansi str))
  (for/sum ([c (in-string cleaned)])
    (char-width c)))

;; ============================================================================
;; Text Height Calculation
;; ============================================================================

(define (split-lines str)
  (regexp-split #rx"\r?\n" str))

(define (text-height str)
  (length (split-lines str)))

;; ============================================================================
;; Text Wrapping
;; ============================================================================

(define (wrap-text str width)
  (if (<= width 0)
      (list str)
      (apply append
             (for/list ([line (in-list (split-lines str))])
               (wrap-single-line line width)))))

(define (wrap-single-line line width)
  (if (<= (text-width line) width)
      (list line)
      (wrap-line-internal line width)))

(define (wrap-line-internal line width)
  (define words (regexp-split #rx" +" line))
  (define-values (lines current-line current-width)
    (for/fold ([lines '()]
               [current-line ""]
               [current-width 0])
              ([word (in-list words)])
      (define word-width (text-width word))
      (cond
        [(zero? current-width)
         (if (> word-width width)
             (let-values ([(wrapped-lines remainder) (break-long-word word width)])
               (values (append lines wrapped-lines)
                       remainder
                       (text-width remainder)))
             (values lines word word-width))]
        [(<= (+ current-width 1 word-width) width)
         (values lines
                 (string-append current-line " " word)
                 (+ current-width 1 word-width))]
        [else
         (if (> word-width width)
             (let-values ([(wrapped-lines remainder) (break-long-word word width)])
               (values (append lines (list current-line) wrapped-lines)
                       remainder
                       (text-width remainder)))
             (values (append lines (list current-line))
                     word
                     word-width))])))
  (if (zero? current-width)
      lines
      (append lines (list current-line))))

(define (break-long-word word width)
  (define chars (string->list word))
  (let loop ([chars chars]
             [lines '()]
             [current-chars '()]
             [current-width 0])
    (cond
      [(null? chars)
       (if (null? current-chars)
           (values (reverse lines) "")
           (values (reverse lines) (list->string (reverse current-chars))))]
      [else
       (define c (car chars))
       (define cw (char-width c))
       (if (> (+ current-width cw) width)
           (if (null? current-chars)
               (loop (cdr chars)
                     (cons (string c) lines)
                     '()
                     0)
               (loop chars
                     (cons (list->string (reverse current-chars)) lines)
                     '()
                     0))
           (loop (cdr chars)
                 lines
                 (cons c current-chars)
                 (+ current-width cw)))])))

;; ============================================================================
;; Text Truncation
;; ============================================================================

(define (truncate-text str width [ellipsis "…"])
  (define cleaned (strip-ansi str))
  (define current-width (text-width cleaned))
  (if (<= current-width width)
      str
      (let ([ellipsis-width (text-width ellipsis)])
        (if (<= width ellipsis-width)
            (visible-slice ellipsis 0 width)
            (string-append (visible-slice cleaned 0 (- width ellipsis-width))
                           ellipsis)))))

;; ============================================================================
;; Padding Functions
;; ============================================================================

(define (pad-right str width [pad-char #\space])
  (define current-width (text-width str))
  (if (>= current-width width)
      str
      (string-append str (make-string (- width current-width) pad-char))))

(define (pad-left str width [pad-char #\space])
  (define current-width (text-width str))
  (if (>= current-width width)
      str
      (string-append (make-string (- width current-width) pad-char) str)))

(define (pad-center str width [pad-char #\space])
  (define current-width (text-width str))
  (if (>= current-width width)
      str
      (let* ([total-padding (- width current-width)]
             [left-padding (quotient total-padding 2)]
             [right-padding (- total-padding left-padding)])
        (string-append (make-string left-padding pad-char)
                       str
                       (make-string right-padding pad-char)))))

;; ============================================================================
;; Line Utilities
;; ============================================================================

(define (max-line-width str)
  (apply max 0 (map text-width (split-lines str))))

(define (visible-slice str start [end #f])
  (define cleaned (strip-ansi str))
  (define chars (string->list cleaned))
  (define target-end (or end (text-width cleaned)))
  
  (define-values (result _ _2)
    (for/fold ([result '()]
               [pos 0]
               [done? #f])
              ([c (in-list chars)]
               #:break done?)
      (define cw (char-width c))
      (define next-pos (+ pos cw))
      (cond
        [(>= pos target-end)
         (values result pos #t)]
        [(< pos start)
         (values result next-pos #f)]
        [else
         (values (cons c result) next-pos #f)])))
  (list->string (reverse result)))

;; ============================================================================
;; Tests
;; ============================================================================

(module+ test
  (require rackunit)
  
  (test-case "strip-ansi removes escape sequences"
    (check-equal? (strip-ansi "\e[31mred\e[0m") "red")
    (check-equal? (strip-ansi "\e[1;32;40mbold green\e[0m") "bold green")
    (check-equal? (strip-ansi "no escapes") "no escapes")
    (check-equal? (strip-ansi "\e[38;5;196mcolor\e[0m") "color")
    (check-equal? (strip-ansi "\e[38;2;255;0;0mtrue\e[0m") "true"))
  
  (test-case "char-width handles different character types"
    (check-equal? (char-width #\a) 1)
    (check-equal? (char-width #\space) 1)
    (check-equal? (char-width #\中) 2)
    (check-equal? (char-width #\日) 2)
    (check-equal? (char-width #\tab) 0)
    (check-equal? (char-width #\nul) 0))
  
  (test-case "text-width calculates display width"
    (check-equal? (text-width "hello") 5)
    (check-equal? (text-width "中文") 4)
    (check-equal? (text-width "\e[31mhello\e[0m") 5)
    (check-equal? (text-width "\e[1mtest\e[0m 中文") 9)
    (check-equal? (text-width "") 0))
  
  (test-case "text-height counts lines"
    (check-equal? (text-height "one") 1)
    (check-equal? (text-height "one\ntwo") 2)
    (check-equal? (text-height "one\r\ntwo\nthree") 3)
    (check-equal? (text-height "") 1))
  
  (test-case "split-lines handles different line endings"
    (check-equal? (split-lines "a\nb\nc") '("a" "b" "c"))
    (check-equal? (split-lines "a\r\nb\r\nc") '("a" "b" "c"))
    (check-equal? (split-lines "single") '("single"))
    (check-equal? (split-lines "") '("")))
  
  (test-case "wrap-text wraps at width"
    (check-equal? (wrap-text "hello world" 20) '("hello world"))
    (check-equal? (wrap-text "hello world" 5) '("hello" "world"))
    (check-equal? (wrap-text "a b c d" 3) '("a b" "c d"))
    (check-equal? (wrap-text "中文测试" 4) '("中文" "测试")))
  
  (test-case "wrap-text handles long words"
    (check-equal? (wrap-text "abcdefghij" 4) '("abcd" "efgh" "ij"))
    (check-equal? (wrap-text "ab cdefgh" 4) '("ab" "cdef" "gh")))
  
  (test-case "truncate-text truncates with ellipsis"
    (check-equal? (truncate-text "hello" 10) "hello")
    (check-equal? (truncate-text "hello world" 8) "hello w…")
    (check-equal? (truncate-text "hello" 3) "he…")
    (check-equal? (truncate-text "hello" 1) "…")
    (check-equal? (truncate-text "hello" 5 "...") "hello")
    (check-equal? (truncate-text "hello!" 5 "...") "he..."))
  
  (test-case "pad-right pads to width"
    (check-equal? (pad-right "hi" 5) "hi   ")
    (check-equal? (pad-right "hello" 3) "hello")
    (check-equal? (pad-right "a" 4 #\-) "a---"))
  
  (test-case "pad-left pads to width"
    (check-equal? (pad-left "hi" 5) "   hi")
    (check-equal? (pad-left "hello" 3) "hello")
    (check-equal? (pad-left "a" 4 #\-) "---a"))
  
  (test-case "pad-center centers text"
    (check-equal? (pad-center "hi" 6) "  hi  ")
    (check-equal? (pad-center "hi" 5) " hi  ")
    (check-equal? (pad-center "hello" 3) "hello"))
  
  (test-case "max-line-width finds widest line"
    (check-equal? (max-line-width "short\nlonger\nmed") 6)
    (check-equal? (max-line-width "only") 4)
    (check-equal? (max-line-width "") 0)
    (check-equal? (max-line-width "中\n文") 2))
  
  (test-case "visible-slice extracts by display position"
    (check-equal? (visible-slice "hello" 0 3) "hel")
    (check-equal? (visible-slice "hello" 2 4) "ll")
    (check-equal? (visible-slice "hello" 2) "llo")
    (check-equal? (visible-slice "中文测试" 0 2) "中")
    (check-equal? (visible-slice "中文测试" 2 4) "文"))
  
  (test-case "visible-slice strips ANSI before slicing"
    (check-equal? (visible-slice "\e[31mhello\e[0m" 0 3) "hel")
    (check-equal? (visible-slice "\e[1mtest\e[0m" 1 3) "es")))
