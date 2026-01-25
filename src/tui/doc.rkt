#lang racket/base

(provide (struct-out doc-text)
         (struct-out doc-block)
         (struct-out doc-row)
         (struct-out doc-col)
         (struct-out doc-spacer)
         (struct-out doc-overlay)
         (struct-out doc-empty)
         (struct-out flex)
         doc?
         txt text
         box block
         row col
         spacer hspace vspace
         hjoin vjoin
         beside above
         stack
         with-flex
         with-style
         doc-style
         doc-flex)

(require "style.rkt"
         "text/measure.rkt"
         racket/match
         racket/list)

(struct doc-text (content style) #:transparent)
(struct doc-block (child style) #:transparent)
(struct doc-row (children style) #:transparent)
(struct doc-col (children style) #:transparent)
(struct doc-spacer (width height grow) #:transparent)
(struct doc-overlay (children) #:transparent)
(struct doc-empty () #:transparent)

(struct flex (grow shrink basis) #:transparent)

(define default-flex (flex 0 1 #f))

(define (doc? v)
  (or (doc-text? v)
      (doc-block? v)
      (doc-row? v)
      (doc-col? v)
      (doc-spacer? v)
      (doc-overlay? v)
      (doc-empty? v)))

(define (txt content [st #f])
  (doc-text (if (string? content) content (~a content))
            (or st empty-style)))

(define text txt)

(define (box child [st #f])
  (doc-block (if (doc? child) child (txt child))
             (or st empty-style)))

(define block box)

(define (normalize-child c)
  (cond
    [(doc? c) c]
    [(string? c) (txt c)]
    [else (txt (~a c))]))

(define (row . children)
  (doc-row (map normalize-child (flatten children)) empty-style))

(define (col . children)
  (doc-col (map normalize-child (flatten children)) empty-style))

(define (spacer [width #f] [height #f] #:grow [grow 1])
  (doc-spacer width height grow))

(define (hspace width)
  (doc-spacer width 1 0))

(define (vspace height)
  (doc-spacer 1 height 0))

(define (hjoin docs #:sep [sep #f] #:align [align #f])
  (define normalized (map normalize-child docs))
  (define with-sep
    (if sep
        (add-between normalized (normalize-child sep))
        normalized))
  (define r (doc-row with-sep empty-style))
  (if align
      (with-style r (struct-copy style empty-style [valign align]))
      r))

(define (vjoin docs #:sep [sep #f] #:align [align #f])
  (define normalized (map normalize-child docs))
  (define with-sep
    (if sep
        (add-between normalized (normalize-child sep))
        normalized))
  (define c (doc-col with-sep empty-style))
  (if align
      (with-style c (struct-copy style empty-style [align align]))
      c))

(define beside hjoin)
(define above vjoin)

(define (stack . children)
  (doc-overlay (map normalize-child (flatten children))))

(define (with-flex doc #:grow [grow 0] #:shrink [shrink 1] #:basis [basis #f])
  (define f (flex grow shrink basis))
  (match doc
    [(doc-text content st)
     (doc-block (doc-text content st)
                (struct-copy style empty-style))]
    [(doc-block child st)
     (doc-block child st)]
    [(doc-row children st)
     (doc-row children st)]
    [(doc-col children st)
     (doc-col children st)]
    [(doc-spacer w h _)
     (doc-spacer w h grow)]
    [_ doc]))

(define (with-style doc st)
  (match doc
    [(doc-text content old-st)
     (doc-text content (style-inherit old-st st))]
    [(doc-block child old-st)
     (doc-block child (style-inherit old-st st))]
    [(doc-row children old-st)
     (doc-row children (style-inherit old-st st))]
    [(doc-col children old-st)
     (doc-col children (style-inherit old-st st))]
    [_ doc]))

(define (doc-style doc)
  (match doc
    [(doc-text _ st) st]
    [(doc-block _ st) st]
    [(doc-row _ st) st]
    [(doc-col _ st) st]
    [_ empty-style]))

(define (doc-flex doc)
  (match doc
    [(doc-spacer _ _ grow) (flex grow 1 #f)]
    [_ default-flex]))

(define (~a v)
  (cond
    [(string? v) v]
    [else (format "~a" v)]))

(module+ test
  (require rackunit)
  
  (test-case "txt creates doc-text"
    (define d (txt "hello"))
    (check-true (doc-text? d))
    (check-equal? (doc-text-content d) "hello"))
  
  (test-case "txt with style"
    (define st (struct-copy style empty-style [fg 'red]))
    (define d (txt "hello" st))
    (check-equal? (style-fg (doc-text-style d)) 'red))
  
  (test-case "box wraps child"
    (define d (box (txt "inner")))
    (check-true (doc-block? d))
    (check-true (doc-text? (doc-block-child d))))
  
  (test-case "box wraps string"
    (define d (box "hello"))
    (check-true (doc-text? (doc-block-child d))))
  
  (test-case "row creates doc-row"
    (define d (row "a" "b" "c"))
    (check-true (doc-row? d))
    (check-equal? (length (doc-row-children d)) 3))
  
  (test-case "col creates doc-col"
    (define d (col "a" "b"))
    (check-true (doc-col? d))
    (check-equal? (length (doc-col-children d)) 2))
  
  (test-case "spacer with defaults"
    (define d (spacer))
    (check-true (doc-spacer? d))
    (check-false (doc-spacer-width d))
    (check-false (doc-spacer-height d))
    (check-equal? (doc-spacer-grow d) 1))
  
  (test-case "hspace creates fixed width spacer"
    (define d (hspace 5))
    (check-equal? (doc-spacer-width d) 5)
    (check-equal? (doc-spacer-grow d) 0))
  
  (test-case "vspace creates fixed height spacer"
    (define d (vspace 3))
    (check-equal? (doc-spacer-height d) 3))
  
  (test-case "hjoin with separator"
    (define d (hjoin '("a" "b" "c") #:sep "|"))
    (check-equal? (length (doc-row-children d)) 5))
  
  (test-case "vjoin with separator"
    (define d (vjoin '("a" "b") #:sep "-"))
    (check-equal? (length (doc-col-children d)) 3))
  
  (test-case "stack creates overlay"
    (define d (stack "a" "b"))
    (check-true (doc-overlay? d))
    (check-equal? (length (doc-overlay-children d)) 2))
  
  (test-case "with-style merges style"
    (define d (txt "hello"))
    (define styled (with-style d (style-set empty-style #:bold #t)))
    (check-true (style-bold (doc-text-style styled))))
  
  (test-case "doc? predicate"
    (check-true (doc? (txt "hi")))
    (check-true (doc? (box "hi")))
    (check-true (doc? (row "a")))
    (check-true (doc? (col "a")))
    (check-true (doc? (spacer)))
    (check-true (doc? (doc-overlay '())))
    (check-true (doc? (doc-empty)))
    (check-false (doc? "string"))))
