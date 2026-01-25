#lang racket/base

(provide (struct-out constraints)
         (struct-out layout-node)
         (struct-out rect)
         unconstrained
         tight
         loose
         layout
         render)

(require "doc.rkt"
         "style.rkt"
         "text/measure.rkt"
         "program.rkt"
         racket/match
         racket/list
         racket/string
         racket/format)

(struct constraints (min-width max-width min-height max-height) #:transparent)
;; Use rect from program.rkt: (rect x y width height)
(struct layout-node (doc rect children) #:transparent)

(define (unconstrained)
  (constraints 0 +inf.0 0 +inf.0))

(define (tight width height)
  (constraints width width height height))

(define (loose max-width max-height)
  (constraints 0 max-width 0 max-height))

(define (clamp v min-v max-v)
  (max min-v (min max-v v)))

(define (clamp-width w c)
  (clamp w (constraints-min-width c) (constraints-max-width c)))

(define (clamp-height h c)
  (clamp h (constraints-min-height c) (constraints-max-height c)))

(define (measure-text-width doc c)
  (match doc
    [(doc-text content _)
     (define w (text-width content))
     (clamp-width w c)]
    [_ 0]))

(define (measure-text-height doc c available-width)
  (match doc
    [(doc-text content _)
     (define lines (wrap-text content (inexact->exact (floor available-width))))
     (clamp-height (length lines) c)]
    [_ 0]))

(define (get-padding st)
  (define p (and st (style-padding st)))
  (cond
    [(not p) (values 0 0 0 0)]
    [(number? p) (values p p p p)]
    [(and (list? p) (= (length p) 2))
     (values (first p) (first p) (second p) (second p))]
    [(and (list? p) (= (length p) 4))
     (values (first p) (second p) (third p) (fourth p))]
    [else (values 0 0 0 0)]))

(define (get-margin st)
  (define m (and st (style-margin st)))
  (cond
    [(not m) (values 0 0 0 0)]
    [(number? m) (values m m m m)]
    [(and (list? m) (= (length m) 2))
     (values (first m) (first m) (second m) (second m))]
    [(and (list? m) (= (length m) 4))
     (values (first m) (second m) (third m) (fourth m))]
    [else (values 0 0 0 0)]))

(define (has-border? st)
  (and st (style-border-style st)))

(define (border-overhead st)
  (if (has-border? st) 2 0))

(define (layout doc width height)
  (define c (loose width height))
  (layout-doc doc 0 0 c))

(define (layout-doc doc x y c)
  (match doc
    [(doc-empty)
     (layout-node doc (rect x y 0 0) '())]
    
    [(doc-text content st)
     (define w (clamp-width (text-width content) c))
     (define lines (wrap-text content (inexact->exact (floor w))))
     (define h (clamp-height (length lines) c))
     (layout-node doc (rect x y w h) '())]
    
    [(doc-spacer sw sh grow)
     (define w (if sw (clamp-width sw c) (constraints-min-width c)))
     (define h (if sh (clamp-height sh c) (constraints-min-height c)))
     (layout-node doc (rect x y w h) '())]
    
    [(doc-block child st)
     (define-values (pt pb pl pr) (get-padding st))
     (define-values (mt mb ml mr) (get-margin st))
     (define border-w (border-overhead st))
     (define border-h (border-overhead st))
     (define total-h-overhead (+ pl pr ml mr border-w))
     (define total-v-overhead (+ pt pb mt mb border-h))
     
     (define explicit-w (style-width st))
     (define explicit-h (style-height st))
     
     (define inner-max-w (- (constraints-max-width c) total-h-overhead))
     (define inner-max-h (- (constraints-max-height c) total-v-overhead))
     
     (define inner-c
       (constraints 0 (max 0 inner-max-w) 0 (max 0 inner-max-h)))
     
     (define child-x (+ x ml (if (has-border? st) 1 0) pl))
     (define child-y (+ y mt (if (has-border? st) 1 0) pt))
     
     (define child-layout (layout-doc child child-x child-y inner-c))
     (define child-rect (layout-node-rect child-layout))
     
     (define content-w (+ (rect-width child-rect) total-h-overhead))
     (define content-h (+ (rect-height child-rect) total-v-overhead))
     
     (define final-w
       (clamp-width (if explicit-w explicit-w content-w) c))
     (define final-h
       (clamp-height (if explicit-h explicit-h content-h) c))
     
     (layout-node doc (rect x y final-w final-h) (list child-layout))]
    
    [(doc-row children st)
     (layout-row children st x y c)]
    
    [(doc-col children st)
     (layout-col children st x y c)]
    
    [(doc-overlay children)
     (define child-layouts
       (for/list ([child (in-list children)])
         (layout-doc child x y c)))
     (define max-w
       (apply max 0 (map (λ (n) (rect-width (layout-node-rect n))) child-layouts)))
     (define max-h
       (apply max 0 (map (λ (n) (rect-height (layout-node-rect n))) child-layouts)))
     (layout-node doc (rect x y (clamp-width max-w c) (clamp-height max-h c))
                  child-layouts)]
    
    [_ (layout-node doc (rect x y 0 0) '())]))

(define (layout-row children st x y c)
  (define n (length children))
  (when (= n 0)
    (return-row-empty x y c))
  
  (define available-w (constraints-max-width c))
  (define valign (or (and st (style-valign st)) 'top))
  
  (define child-infos
    (for/list ([child (in-list children)])
      (define f (doc-flex child))
      (define grow (flex-grow f))
      (define basis (flex-basis f))
      (define temp-c (constraints 0 available-w 0 (constraints-max-height c)))
      (define temp-layout (layout-doc child 0 0 temp-c))
      (define base-w
        (or basis (rect-width (layout-node-rect temp-layout))))
      (list child grow base-w)))
  
  (define total-base (apply + (map third child-infos)))
  (define total-grow (apply + (map second child-infos)))
  (define remaining (max 0 (- available-w total-base)))
  
  (define final-widths
    (for/list ([info (in-list child-infos)])
      (define grow (second info))
      (define base (third info))
      (define extra
        (if (> total-grow 0)
            (* remaining (/ grow total-grow))
            0))
      (+ base extra)))
  
  (define max-h 0)
  (define layouts-with-heights
    (for/list ([child (in-list children)]
               [w (in-list final-widths)])
      (define child-c (constraints w w 0 (constraints-max-height c)))
      (define child-layout (layout-doc child 0 0 child-c))
      (define h (rect-height (layout-node-rect child-layout)))
      (set! max-h (max max-h h))
      (list child w h)))
  
  (define final-h (clamp-height max-h c))
  
  (define-values (layouts _)
    (for/fold ([acc '()]
               [cur-x x])
              ([info (in-list layouts-with-heights)])
      (define child (first info))
      (define w (second info))
      (define h (third info))
      (define child-y
        (case valign
          [(top) y]
          [(middle) (+ y (/ (- final-h h) 2))]
          [(bottom) (+ y (- final-h h))]
          [(stretch) y]
          [else y]))
      (define child-h (if (eq? valign 'stretch) final-h h))
      (define child-c (constraints w w child-h child-h))
      (define child-layout (layout-doc child cur-x child-y child-c))
      (values (cons child-layout acc)
              (+ cur-x w))))
  
  (define total-w (apply + final-widths))
  (layout-node (doc-row children st)
               (rect x y (clamp-width total-w c) final-h)
               (reverse layouts)))

(define (return-row-empty x y c)
  (layout-node (doc-row '() empty-style) (rect x y 0 0) '()))

(define (layout-col children st x y c)
  (define n (length children))
  (when (= n 0)
    (return-col-empty x y c))
  
  (define available-h (constraints-max-height c))
  (define align (or (and st (style-align st)) 'left))
  
  (define child-infos
    (for/list ([child (in-list children)])
      (define f (doc-flex child))
      (define grow (flex-grow f))
      (define basis (flex-basis f))
      (define temp-c (constraints 0 (constraints-max-width c) 0 available-h))
      (define temp-layout (layout-doc child 0 0 temp-c))
      (define base-h
        (or basis (rect-height (layout-node-rect temp-layout))))
      (list child grow base-h)))
  
  (define total-base (apply + (map third child-infos)))
  (define total-grow (apply + (map second child-infos)))
  (define remaining (max 0 (- available-h total-base)))
  
  (define final-heights
    (for/list ([info (in-list child-infos)])
      (define grow (second info))
      (define base (third info))
      (define extra
        (if (> total-grow 0)
            (* remaining (/ grow total-grow))
            0))
      (+ base extra)))
  
  (define max-w 0)
  (define layouts-with-widths
    (for/list ([child (in-list children)]
               [h (in-list final-heights)])
      (define child-c (constraints 0 (constraints-max-width c) h h))
      (define child-layout (layout-doc child 0 0 child-c))
      (define w (rect-width (layout-node-rect child-layout)))
      (set! max-w (max max-w w))
      (list child w h)))
  
  (define final-w (clamp-width max-w c))
  
  (define-values (layouts _)
    (for/fold ([acc '()]
               [cur-y y])
              ([info (in-list layouts-with-widths)])
      (define child (first info))
      (define w (second info))
      (define h (third info))
      (define child-x
        (case align
          [(left) x]
          [(center) (+ x (/ (- final-w w) 2))]
          [(right) (+ x (- final-w w))]
          [(stretch) x]
          [else x]))
      (define child-w (if (eq? align 'stretch) final-w w))
      (define child-c (constraints child-w child-w h h))
      (define child-layout (layout-doc child child-x cur-y child-c))
      (values (cons child-layout acc)
              (+ cur-y h))))
  
  (define total-h (apply + final-heights))
  (layout-node (doc-col children st)
               (rect x y final-w (clamp-height total-h c))
               (reverse layouts)))

(define (return-col-empty x y c)
  (layout-node (doc-col '() empty-style) (rect x y 0 0) '()))

(struct buffer (width height cells) #:transparent #:mutable)

(define (make-buffer width height [fill-char #\space])
  (define cells
    (for/vector ([_ (in-range height)])
      (make-vector width (cons fill-char empty-style))))
  (buffer width height cells))

(define (buffer-set! buf x y char st)
  (when (and (>= x 0) (< x (buffer-width buf))
             (>= y 0) (< y (buffer-height buf)))
    (define row (vector-ref (buffer-cells buf) (inexact->exact (floor y))))
    (vector-set! row (inexact->exact (floor x)) (cons char st))))

(define (buffer-get buf x y)
  (if (and (>= x 0) (< x (buffer-width buf))
           (>= y 0) (< y (buffer-height buf)))
      (vector-ref (vector-ref (buffer-cells buf) (inexact->exact (floor y)))
                  (inexact->exact (floor x)))
      (cons #\space empty-style)))

(define (render doc width height)
  (define buf (make-buffer width height))
  (define root-layout (layout doc width height))
  (render-node root-layout buf)
  (buffer->string buf))

(define (render-node node buf)
  (define doc (layout-node-doc node))
  (define r (layout-node-rect node))
  (define x (inexact->exact (floor (rect-x r))))
  (define y (inexact->exact (floor (rect-y r))))
  (define w (inexact->exact (floor (rect-width r))))
  (define h (inexact->exact (floor (rect-height r))))
  
  (match doc
    [(doc-text content st)
     (render-text content st x y w h buf)]
    
    [(doc-spacer _ _ _)
     (void)]
    
    [(doc-block child st)
     (render-block st x y w h buf)
     (for ([child-node (in-list (layout-node-children node))])
       (render-node child-node buf))]
    
    [(doc-row _ st)
     (for ([child-node (in-list (layout-node-children node))])
       (render-node child-node buf))]
    
    [(doc-col _ st)
     (for ([child-node (in-list (layout-node-children node))])
       (render-node child-node buf))]
    
    [(doc-overlay children)
     (for ([child-node (in-list (layout-node-children node))])
       (render-node child-node buf))]
    
    [(doc-empty) (void)]
    
    [_ (void)]))

(define (render-text content st x y w h buf)
  (define lines (wrap-text content w))
  (for ([line (in-list lines)]
        [row (in-naturals)])
    (when (< row h)
      (for ([c (in-string line)]
            [col (in-naturals)])
        (when (< col w)
          (buffer-set! buf (+ x col) (+ y row) c st))))))

(define (render-block st x y w h buf)
  (when (has-border? st)
    (define bs (style-border-style st))
    (for ([col (in-range 1 (- w 1))])
      (buffer-set! buf (+ x col) y
                   (string-ref (border-top bs) 0) st)
      (buffer-set! buf (+ x col) (+ y h -1)
                   (string-ref (border-bottom bs) 0) st))
    (for ([row (in-range 1 (- h 1))])
      (buffer-set! buf x (+ y row)
                   (string-ref (border-left bs) 0) st)
      (buffer-set! buf (+ x w -1) (+ y row)
                   (string-ref (border-right bs) 0) st))
    (buffer-set! buf x y (string-ref (border-top-left bs) 0) st)
    (buffer-set! buf (+ x w -1) y (string-ref (border-top-right bs) 0) st)
    (buffer-set! buf x (+ y h -1) (string-ref (border-bottom-left bs) 0) st)
    (buffer-set! buf (+ x w -1) (+ y h -1) (string-ref (border-bottom-right bs) 0) st)))

(define (style->ansi st)
  (string-append
   (color->ansi-fg (style-fg st))
   (color->ansi-bg (style-bg st))
   (if (style-bold st) "\033[1m" "")
   (if (style-dim st) "\033[2m" "")
   (if (style-italic st) "\033[3m" "")
   (if (style-underline st) "\033[4m" "")
   (if (style-blink st) "\033[5m" "")
   (if (style-reverse st) "\033[7m" "")
   (if (style-strikethrough st) "\033[9m" "")))

(define (buffer->string buf)
  (define lines
    (for/list ([row (in-range (buffer-height buf))])
      (define row-vec (vector-ref (buffer-cells buf) row))
      (define chars
        (for/list ([col (in-range (buffer-width buf))])
          (define cell (vector-ref row-vec col))
          (define char (car cell))
          (define st (cdr cell))
          (define ansi (style->ansi st))
          (if (non-empty-string? ansi)
              (string-append ansi (string char) "\033[0m")
              (string char))))
      (string-join chars "")))
  (string-join lines "\n"))

(module+ test
  (require rackunit)
  
  (test-case "unconstrained creates no limits"
    (define c (unconstrained))
    (check-equal? (constraints-min-width c) 0)
    (check-equal? (constraints-max-width c) +inf.0))
  
  (test-case "tight creates exact constraints"
    (define c (tight 10 5))
    (check-equal? (constraints-min-width c) 10)
    (check-equal? (constraints-max-width c) 10)
    (check-equal? (constraints-min-height c) 5)
    (check-equal? (constraints-max-height c) 5))
  
  (test-case "loose creates max-only constraints"
    (define c (loose 80 24))
    (check-equal? (constraints-min-width c) 0)
    (check-equal? (constraints-max-width c) 80))
  
  (test-case "layout text node"
    (define d (txt "hello"))
    (define node (layout d 80 24))
    (check-equal? (rect-width (layout-node-rect node)) 5)
    (check-equal? (rect-height (layout-node-rect node)) 1))
  
  (test-case "layout empty node"
    (define d (doc-empty))
    (define node (layout d 80 24))
    (check-equal? (rect-width (layout-node-rect node)) 0)
    (check-equal? (rect-height (layout-node-rect node)) 0))
  
  (test-case "layout row distributes width"
    (define d (row (txt "a") (txt "b") (txt "c")))
    (define node (layout d 80 24))
    (check-equal? (length (layout-node-children node)) 3)
    (check-equal? (rect-width (layout-node-rect node)) 3))
  
  (test-case "layout col stacks vertically"
    (define d (col (txt "line1") (txt "line2")))
    (define node (layout d 80 24))
    (check-equal? (length (layout-node-children node)) 2)
    (check-equal? (rect-height (layout-node-rect node)) 2))
  
  (test-case "layout block with padding"
    (define st (style-set empty-style #:padding '(1 1 1 1)))
    (define d (doc-block (txt "hi") st))
    (define node (layout d 80 24))
    (check-true (>= (rect-width (layout-node-rect node)) 4))
    (check-true (>= (rect-height (layout-node-rect node)) 3)))
  
  (test-case "layout block with border"
    (define st (style-set empty-style #:border rounded-border))
    (define d (doc-block (txt "hi") st))
    (define node (layout d 80 24))
    (check-true (>= (rect-width (layout-node-rect node)) 4))
    (check-true (>= (rect-height (layout-node-rect node)) 3)))
  
  (test-case "layout overlay stacks children"
    (define d (stack (txt "a") (txt "bbb")))
    (define node (layout d 80 24))
    (check-equal? (length (layout-node-children node)) 2)
    (check-equal? (rect-width (layout-node-rect node)) 3))
  
  (test-case "layout spacer with fixed size"
    (define d (hspace 10))
    (define node (layout d 80 24))
    (check-equal? (rect-width (layout-node-rect node)) 10))
  
  (test-case "render simple text"
    (define d (txt "hi"))
    (define result (render d 5 1))
    (check-true (string-contains? result "hi")))
  
  (test-case "render row"
    (define d (row (txt "a") (txt "b")))
    (define result (render d 5 1))
    (check-true (string-contains? result "a"))
    (check-true (string-contains? result "b")))
  
  (test-case "render col"
    (define d (col (txt "a") (txt "b")))
    (define result (render d 5 2))
    (define lines (string-split result "\n"))
    (check-equal? (length lines) 2))
  
  (test-case "row with flex spacer"
    (define d (row (txt "L") (spacer) (txt "R")))
    (define node (layout d 10 1))
    (define children (layout-node-children node))
    (check-equal? (length children) 3)
    (define left-r (layout-node-rect (first children)))
    (define right-r (layout-node-rect (third children)))
    (check-equal? (rect-x left-r) 0)
    (check-true (> (rect-x right-r) 1)))
  
  (test-case "nested row and col"
    (define d (col (row (txt "a") (txt "b"))
                   (row (txt "c") (txt "d"))))
    (define node (layout d 10 5))
    (check-equal? (length (layout-node-children node)) 2)
    (define first-row (first (layout-node-children node)))
    (check-equal? (length (layout-node-children first-row)) 2)))
