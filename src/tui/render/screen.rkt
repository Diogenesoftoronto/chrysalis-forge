#lang racket/base
(provide (struct-out cell)
         (struct-out screen)
         cell-equal?
         make-cell
         empty-cell
         make-screen
         screen-resize
         screen-clear
         screen-set-cell!
         screen-get-cell
         screen-write-string!
         screen-write-doc!
         screen-diff
         screen-render-diff
         screen-render-full
         screen-set-cursor!
         screen-show-cursor!
         screen-hide-cursor!
         screen-flush
         screen-lines
         make-double-buffer
         double-buffer-front
         double-buffer-back
         swap-buffers!)

(require racket/match
         racket/string
         racket/format
         racket/port
         "../style.rkt"
         "../text/measure.rkt"
         "../layout.rkt"
         "../doc.rkt"
         "../terminal.rkt")

;; ============================================================================
;; Cell Representation
;; ============================================================================

(struct cell (char fg bg bold dim italic underline strikethrough blink reverse)
  #:transparent)

(define empty-cell
  (cell " " #f #f #f #f #f #f #f #f #f))

(define (make-cell char
                   #:fg [fg #f]
                   #:bg [bg #f]
                   #:bold [bold #f]
                   #:dim [dim #f]
                   #:italic [italic #f]
                   #:underline [underline #f]
                   #:strikethrough [strikethrough #f]
                   #:blink [blink #f]
                   #:reverse [rev #f])
  (cell (if (char? char) (string char) char)
        fg bg bold dim italic underline strikethrough blink rev))

(define (cell-equal? a b)
  (and (equal? (cell-char a) (cell-char b))
       (equal? (cell-fg a) (cell-fg b))
       (equal? (cell-bg a) (cell-bg b))
       (equal? (cell-bold a) (cell-bold b))
       (equal? (cell-dim a) (cell-dim b))
       (equal? (cell-italic a) (cell-italic b))
       (equal? (cell-underline a) (cell-underline b))
       (equal? (cell-strikethrough a) (cell-strikethrough b))
       (equal? (cell-blink a) (cell-blink b))
       (equal? (cell-reverse a) (cell-reverse b))))

(define (style->cell-attrs st)
  (if st
      (values (style-fg st)
              (style-bg st)
              (style-bold st)
              (style-dim st)
              (style-italic st)
              (style-underline st)
              (style-strikethrough st)
              (style-blink st)
              (style-reverse st))
      (values #f #f #f #f #f #f #f #f #f)))

(define (cell-from-char+style ch st)
  (define-values (fg bg bold dim italic underline strike blink rev)
    (style->cell-attrs st))
  (cell (if (char? ch) (string ch) ch)
        fg bg bold dim italic underline strike blink rev))

;; ============================================================================
;; Screen Buffer
;; ============================================================================

(struct screen (width height cells cursor-x cursor-y cursor-visible? output-buffer)
  #:mutable #:transparent)

(define (make-screen width height)
  (define cells
    (for/vector ([_ (in-range height)])
      (make-vector width empty-cell)))
  (screen width height cells 0 0 #t (open-output-bytes)))

(define (screen-resize scr new-width new-height)
  (define old-width (screen-width scr))
  (define old-height (screen-height scr))
  (define old-cells (screen-cells scr))
  (define new-cells
    (for/vector ([row (in-range new-height)])
      (define new-row (make-vector new-width empty-cell))
      (when (< row old-height)
        (define old-row (vector-ref old-cells row))
        (for ([col (in-range (min new-width old-width))])
          (vector-set! new-row col (vector-ref old-row col))))
      new-row))
  (set-screen-width! scr new-width)
  (set-screen-height! scr new-height)
  (set-screen-cells! scr new-cells)
  (set-screen-cursor-x! scr (min (screen-cursor-x scr) (max 0 (sub1 new-width))))
  (set-screen-cursor-y! scr (min (screen-cursor-y scr) (max 0 (sub1 new-height))))
  scr)

;; ============================================================================
;; Buffer Operations
;; ============================================================================

(define (screen-clear scr [fill-cell empty-cell])
  (define w (screen-width scr))
  (define h (screen-height scr))
  (for ([row (in-range h)])
    (define row-vec (vector-ref (screen-cells scr) row))
    (for ([col (in-range w)])
      (vector-set! row-vec col fill-cell))))

(define (screen-set-cell! scr x y c)
  (when (and (>= x 0) (< x (screen-width scr))
             (>= y 0) (< y (screen-height scr)))
    (vector-set! (vector-ref (screen-cells scr) y) x c)))

(define (screen-get-cell scr x y)
  (if (and (>= x 0) (< x (screen-width scr))
           (>= y 0) (< y (screen-height scr)))
      (vector-ref (vector-ref (screen-cells scr) y) x)
      empty-cell))

(define (screen-write-string! scr x y str [st #f])
  (define cleaned (strip-ansi str))
  (define-values (fg bg bold dim italic underline strike blink rev)
    (style->cell-attrs st))
  (define w (screen-width scr))
  (define h (screen-height scr))
  (when (and (>= y 0) (< y h))
    (for/fold ([col x])
              ([c (in-string cleaned)])
      (define cw (char-width c))
      (cond
        [(and (>= col 0) (< col w) (> cw 0))
         (screen-set-cell! scr col y
                           (cell (string c) fg bg bold dim italic underline strike blink rev))
         (when (= cw 2)
           (when (< (+ col 1) w)
             (screen-set-cell! scr (+ col 1) y
                               (cell "" fg bg #f #f #f #f #f #f #f))))
         (+ col cw)]
        [else (+ col cw)]))))

(define (screen-write-doc! scr doc)
  (define w (screen-width scr))
  (define h (screen-height scr))
  (define root-layout (layout doc w h))
  (render-layout-to-screen root-layout scr))

(define (render-layout-to-screen node scr)
  (define doc (layout-node-doc node))
  (define r (layout-node-rect node))
  (define x (inexact->exact (floor (rect-x r))))
  (define y (inexact->exact (floor (rect-y r))))
  (define w (inexact->exact (floor (rect-width r))))
  (define h (inexact->exact (floor (rect-height r))))

  (match doc
    [(doc-text content st)
     (define lines (wrap-text content w))
     (for ([line (in-list lines)]
           [row (in-naturals)])
       (when (< row h)
         (screen-write-string! scr x (+ y row) line st)))]

    [(doc-block child st)
     (when (style-border-style st)
       (render-border-to-screen st x y w h scr))
     (for ([child-node (in-list (layout-node-children node))])
       (render-layout-to-screen child-node scr))]

    [(doc-row _ _)
     (for ([child-node (in-list (layout-node-children node))])
       (render-layout-to-screen child-node scr))]

    [(doc-col _ _)
     (for ([child-node (in-list (layout-node-children node))])
       (render-layout-to-screen child-node scr))]

    [(doc-overlay _)
     (for ([child-node (in-list (layout-node-children node))])
       (render-layout-to-screen child-node scr))]

    [_ (void)]))

(define (render-border-to-screen st x y w h scr)
  (define bs (get-border-struct st))
  (when bs
    (define border-st (style-set empty-style
                                 #:fg (style-border-fg st)
                                 #:bg (style-border-bg st)))
    (for ([col (in-range 1 (- w 1))])
      (screen-write-string! scr (+ x col) y (border-top bs) border-st)
      (screen-write-string! scr (+ x col) (+ y h -1) (border-bottom bs) border-st))
    (for ([row (in-range 1 (- h 1))])
      (screen-write-string! scr x (+ y row) (border-left bs) border-st)
      (screen-write-string! scr (+ x w -1) (+ y row) (border-right bs) border-st))
    (screen-write-string! scr x y (border-top-left bs) border-st)
    (screen-write-string! scr (+ x w -1) y (border-top-right bs) border-st)
    (screen-write-string! scr x (+ y h -1) (border-bottom-left bs) border-st)
    (screen-write-string! scr (+ x w -1) (+ y h -1) (border-bottom-right bs) border-st)))

;; ============================================================================
;; Diff Rendering
;; ============================================================================

(struct change (y x-start cells) #:transparent)

(define (screen-diff old-scr new-scr)
  (define w (screen-width new-scr))
  (define h (screen-height new-scr))
  (define changes '())

  (for ([y (in-range h)])
    (define old-row (if (< y (screen-height old-scr))
                        (vector-ref (screen-cells old-scr) y)
                        #f))
    (define new-row (vector-ref (screen-cells new-scr) y))
    (define run-start #f)
    (define run-cells '())

    (for ([x (in-range w)])
      (define new-cell (vector-ref new-row x))
      (define old-cell (if old-row
                           (if (< x (screen-width old-scr))
                               (vector-ref old-row x)
                               empty-cell)
                           empty-cell))
      (define changed? (not (cell-equal? old-cell new-cell)))

      (cond
        [changed?
         (unless run-start
           (set! run-start x))
         (set! run-cells (cons new-cell run-cells))]
        [run-start
         (set! changes (cons (change y run-start (reverse run-cells)) changes))
         (set! run-start #f)
         (set! run-cells '())]))

    (when run-start
      (set! changes (cons (change y run-start (reverse run-cells)) changes))))

  (reverse changes))

(define (cell->ansi c)
  (define out (open-output-string))
  (define codes '())

  (when (cell-bold c) (set! codes (cons "1" codes)))
  (when (cell-dim c) (set! codes (cons "2" codes)))
  (when (cell-italic c) (set! codes (cons "3" codes)))
  (when (cell-underline c) (set! codes (cons "4" codes)))
  (when (cell-blink c) (set! codes (cons "5" codes)))
  (when (cell-reverse c) (set! codes (cons "7" codes)))
  (when (cell-strikethrough c) (set! codes (cons "9" codes)))

  (display (color->ansi-fg (cell-fg c)) out)
  (display (color->ansi-bg (cell-bg c)) out)

  (when (pair? codes)
    (display (string-append "\e[" (string-join (reverse codes) ";") "m") out))

  (display (cell-char c) out)
  (display "\e[0m" out)

  (get-output-string out))

(define (cells-same-style? a b)
  (and (equal? (cell-fg a) (cell-fg b))
       (equal? (cell-bg a) (cell-bg b))
       (equal? (cell-bold a) (cell-bold b))
       (equal? (cell-dim a) (cell-dim b))
       (equal? (cell-italic a) (cell-italic b))
       (equal? (cell-underline a) (cell-underline b))
       (equal? (cell-strikethrough a) (cell-strikethrough b))
       (equal? (cell-blink a) (cell-blink b))
       (equal? (cell-reverse a) (cell-reverse b))))

(define (render-cells-optimized cells out)
  (when (pair? cells)
    (define first-cell (car cells))
    (define codes '())

    (when (cell-bold first-cell) (set! codes (cons "1" codes)))
    (when (cell-dim first-cell) (set! codes (cons "2" codes)))
    (when (cell-italic first-cell) (set! codes (cons "3" codes)))
    (when (cell-underline first-cell) (set! codes (cons "4" codes)))
    (when (cell-blink first-cell) (set! codes (cons "5" codes)))
    (when (cell-reverse first-cell) (set! codes (cons "7" codes)))
    (when (cell-strikethrough first-cell) (set! codes (cons "9" codes)))

    (display (color->ansi-fg (cell-fg first-cell)) out)
    (display (color->ansi-bg (cell-bg first-cell)) out)
    (when (pair? codes)
      (display (string-append "\e[" (string-join (reverse codes) ";") "m") out))

    (let loop ([cells cells] [current-style first-cell])
      (cond
        [(null? cells)
         (display "\e[0m" out)]
        [else
         (define c (car cells))
         (cond
           [(cells-same-style? current-style c)
            (display (cell-char c) out)
            (loop (cdr cells) current-style)]
           [else
            (display "\e[0m" out)
            (render-cells-optimized cells out)])]))))

(define (screen-render-diff scr changes)
  (define out (screen-output-buffer scr))
  (for ([ch (in-list changes)])
    (define y (change-y ch))
    (define x (change-x-start ch))
    (define cells (change-cells ch))
    (display (cursor-to (+ y 1) (+ x 1)) out)
    (render-cells-optimized cells out)))

(define (screen-render-full scr)
  (define out (screen-output-buffer scr))
  (define w (screen-width scr))
  (define h (screen-height scr))

  (display (cursor-to 1 1) out)
  (display (clear-screen) out)

  (for ([y (in-range h)])
    (display (cursor-to (+ y 1) 1) out)
    (define row (vector-ref (screen-cells scr) y))
    (define cells (for/list ([x (in-range w)])
                    (vector-ref row x)))
    (render-cells-optimized cells out)))

;; ============================================================================
;; Cursor Management
;; ============================================================================

(define (screen-set-cursor! scr x y)
  (set-screen-cursor-x! scr (max 0 (min x (sub1 (screen-width scr)))))
  (set-screen-cursor-y! scr (max 0 (min y (sub1 (screen-height scr))))))

(define (screen-show-cursor! scr)
  (set-screen-cursor-visible?! scr #t)
  (display "\e[?25h" (screen-output-buffer scr)))

(define (screen-hide-cursor! scr)
  (set-screen-cursor-visible?! scr #f)
  (display "\e[?25l" (screen-output-buffer scr)))

(define (screen-lines scr)
  (define w (screen-width scr))
  (define h (screen-height scr))
  (for/list ([y (in-range h)])
    (define row (vector-ref (screen-cells scr) y))
    (define cells (vector->list row))
    (define out (open-output-string))
    (render-cells-optimized cells out)
    (get-output-string out)))

;; ============================================================================
;; Terminal Output
;; ============================================================================

(define (screen-flush scr)
  (define buf (screen-output-buffer scr))
  (define bytes (get-output-bytes buf #t))

  (when (screen-cursor-visible? scr)
    (define cursor-seq (cursor-to (+ (screen-cursor-y scr) 1)
                                  (+ (screen-cursor-x scr) 1)))
    (write-bytes (string->bytes/utf-8 cursor-seq)))

  (write-bytes bytes)
  (flush-output)
  (set-screen-output-buffer! scr (open-output-bytes)))

;; ============================================================================
;; Double Buffering
;; ============================================================================

(struct double-buffer (front back) #:mutable #:transparent)

(define (make-double-buffer width height)
  (double-buffer (make-screen width height)
                 (make-screen width height)))

(define (swap-buffers! db)
  (define front (double-buffer-front db))
  (define back (double-buffer-back db))
  (define changes (screen-diff front back))
  (screen-render-diff back changes)
  (screen-flush back)
  (set-double-buffer-front! db back)
  (set-double-buffer-back! db front)
  (screen-clear front)
  changes)

;; ============================================================================
;; Tests
;; ============================================================================

(module+ test
  (require rackunit)

  (test-case "cell-equal? compares all fields"
             (define c1 (make-cell #\a #:fg 'red #:bold #t))
             (define c2 (make-cell #\a #:fg 'red #:bold #t))
             (define c3 (make-cell #\a #:fg 'blue #:bold #t))
             (define c4 (make-cell #\b #:fg 'red #:bold #t))
             (check-true (cell-equal? c1 c2))
             (check-false (cell-equal? c1 c3))
             (check-false (cell-equal? c1 c4)))

  (test-case "empty-cell has correct defaults"
             (check-equal? (cell-char empty-cell) " ")
             (check-false (cell-fg empty-cell))
             (check-false (cell-bold empty-cell)))

  (test-case "make-screen creates correct dimensions"
             (define scr (make-screen 80 24))
             (check-equal? (screen-width scr) 80)
             (check-equal? (screen-height scr) 24)
             (check-equal? (vector-length (screen-cells scr)) 24)
             (check-equal? (vector-length (vector-ref (screen-cells scr) 0)) 80))

  (test-case "screen-set-cell! and screen-get-cell work"
             (define scr (make-screen 10 10))
             (define c (make-cell #\X #:fg 'red))
             (screen-set-cell! scr 5 5 c)
             (check-true (cell-equal? (screen-get-cell scr 5 5) c))
             (check-true (cell-equal? (screen-get-cell scr 0 0) empty-cell)))

  (test-case "screen-set-cell! ignores out of bounds"
             (define scr (make-screen 10 10))
             (define c (make-cell #\X))
             (screen-set-cell! scr -1 5 c)
             (screen-set-cell! scr 5 -1 c)
             (screen-set-cell! scr 10 5 c)
             (screen-set-cell! scr 5 10 c)
             (check-true (cell-equal? (screen-get-cell scr 0 0) empty-cell)))

  (test-case "screen-get-cell returns empty-cell for out of bounds"
             (define scr (make-screen 10 10))
             (check-true (cell-equal? (screen-get-cell scr -1 0) empty-cell))
             (check-true (cell-equal? (screen-get-cell scr 100 0) empty-cell)))

  (test-case "screen-clear fills with empty cells"
             (define scr (make-screen 5 5))
             (screen-set-cell! scr 2 2 (make-cell #\X))
             (screen-clear scr)
             (check-true (cell-equal? (screen-get-cell scr 2 2) empty-cell)))

  (test-case "screen-resize preserves content"
             (define scr (make-screen 10 10))
             (define c (make-cell #\X #:fg 'blue))
             (screen-set-cell! scr 5 5 c)
             (screen-resize scr 20 20)
             (check-equal? (screen-width scr) 20)
             (check-equal? (screen-height scr) 20)
             (check-true (cell-equal? (screen-get-cell scr 5 5) c)))

  (test-case "screen-resize clips cursor"
             (define scr (make-screen 20 20))
             (screen-set-cursor! scr 15 15)
             (screen-resize scr 10 10)
             (check-true (< (screen-cursor-x scr) 10))
             (check-true (< (screen-cursor-y scr) 10)))

  (test-case "screen-write-string! writes characters"
             (define scr (make-screen 10 5))
             (screen-write-string! scr 0 0 "hello")
             (check-equal? (cell-char (screen-get-cell scr 0 0)) "h")
             (check-equal? (cell-char (screen-get-cell scr 1 0)) "e")
             (check-equal? (cell-char (screen-get-cell scr 4 0)) "o"))

  (test-case "screen-write-string! applies style"
             (define scr (make-screen 10 5))
             (define st (style-set empty-style #:fg 'red #:bold #t))
             (screen-write-string! scr 0 0 "hi" st)
             (define c (screen-get-cell scr 0 0))
             (check-equal? (cell-fg c) 'red)
             (check-true (cell-bold c)))

  (test-case "screen-diff detects changes"
             (define old (make-screen 5 5))
             (define new (make-screen 5 5))
             (screen-set-cell! new 2 2 (make-cell #\X))
             (define changes (screen-diff old new))
             (check-equal? (length changes) 1)
             (check-equal? (change-y (car changes)) 2)
             (check-equal? (change-x-start (car changes)) 2))

  (test-case "screen-diff batches consecutive changes"
             (define old (make-screen 10 5))
             (define new (make-screen 10 5))
             (screen-write-string! new 0 0 "hello")
             (define changes (screen-diff old new))
             (check-equal? (length changes) 1)
             (check-equal? (length (change-cells (car changes))) 5))

  (test-case "screen-diff returns empty for identical screens"
             (define scr1 (make-screen 5 5))
             (define scr2 (make-screen 5 5))
             (define changes (screen-diff scr1 scr2))
             (check-equal? (length changes) 0))

  (test-case "screen-set-cursor! clamps to bounds"
             (define scr (make-screen 10 10))
             (screen-set-cursor! scr 100 100)
             (check-equal? (screen-cursor-x scr) 9)
             (check-equal? (screen-cursor-y scr) 9)
             (screen-set-cursor! scr -5 -5)
             (check-equal? (screen-cursor-x scr) 0)
             (check-equal? (screen-cursor-y scr) 0))

  (test-case "make-double-buffer creates two screens"
             (define db (make-double-buffer 80 24))
             (check-true (screen? (double-buffer-front db)))
             (check-true (screen? (double-buffer-back db)))))
