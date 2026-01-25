#lang racket/base

(require racket/match
         racket/string
         racket/set
         racket/list
         "../event.rkt"
         "../doc.rkt"
         "../style.rkt"
         "../text/measure.rkt")

(provide (struct-out viewport-model)
         
         ;; Messages
         (struct-out viewport-scroll-msg)
         (struct-out viewport-set-content-msg)
         
         ;; Init/Update/View
         viewport-init
         viewport-update
         viewport-view
         
         ;; Content management
         viewport-set-content
         viewport-scroll-to
         viewport-scroll-to-bottom
         viewport-scroll-to-top
         
         ;; Queries
         viewport-at-top?
         viewport-at-bottom?
         viewport-scroll-percent
         viewport-content-height
         viewport-visible-lines)

;; ============================================================================
;; Model
;; ============================================================================

(struct viewport-model
  (content width height scroll-x scroll-y show-indicators? style)
  #:transparent)

(define (viewport-init #:width [width 40]
                       #:height [height 10]
                       #:content [content ""]
                       #:show-indicators? [show-indicators? #t]
                       #:style [style empty-style])
  (viewport-model
   content
   width
   height
   0
   0
   show-indicators?
   style))

;; ============================================================================
;; Messages
;; ============================================================================

(struct viewport-scroll-msg (dx dy) #:transparent)
(struct viewport-set-content-msg (content) #:transparent)

;; ============================================================================
;; Update
;; ============================================================================

(define (viewport-update model evt)
  (match evt
    [(viewport-scroll-msg dx dy)
     (values (scroll-by model dx dy) '())]
    
    [(viewport-set-content-msg content)
     (values (viewport-set-content model content) '())]
    
    [(key-event key rune mods _)
     (cond
       ;; Up arrow
       [(eq? key 'up)
        (values (scroll-by model 0 -1) '())]
       
       ;; Down arrow
       [(eq? key 'down)
        (values (scroll-by model 0 1) '())]
       
       ;; Left arrow
       [(eq? key 'left)
        (values (scroll-by model -1 0) '())]
       
       ;; Right arrow
       [(eq? key 'right)
        (values (scroll-by model 1 0) '())]
       
       ;; Page up
       [(eq? key 'page-up)
        (define page-size (max 1 (sub1 (viewport-model-height model))))
        (values (scroll-by model 0 (- page-size)) '())]
       
       ;; Page down
       [(eq? key 'page-down)
        (define page-size (max 1 (sub1 (viewport-model-height model))))
        (values (scroll-by model 0 page-size) '())]
       
       ;; Home - scroll to top
       [(eq? key 'home)
        (values (viewport-scroll-to-top model) '())]
       
       ;; End - scroll to bottom
       [(eq? key 'end)
        (values (viewport-scroll-to-bottom model) '())]
       
       ;; Ctrl+Home - scroll to top-left
       [(and (set-member? mods 'ctrl) (eq? key 'home))
        (values (viewport-scroll-to model 0 0) '())]
       
       ;; Ctrl+End - scroll to bottom-right
       [(and (set-member? mods 'ctrl) (eq? key 'end))
        (values (viewport-scroll-to-bottom model) '())]
       
       ;; j - vim down
       [(and (not (set-member? mods 'ctrl)) (equal? rune #\j))
        (values (scroll-by model 0 1) '())]
       
       ;; k - vim up
       [(and (not (set-member? mods 'ctrl)) (equal? rune #\k))
        (values (scroll-by model 0 -1) '())]
       
       ;; h - vim left
       [(and (not (set-member? mods 'ctrl)) (equal? rune #\h))
        (values (scroll-by model -1 0) '())]
       
       ;; l - vim right
       [(and (not (set-member? mods 'ctrl)) (equal? rune #\l))
        (values (scroll-by model 1 0) '())]
       
       ;; g - vim top
       [(and (not (set-member? mods 'ctrl)) (equal? rune #\g))
        (values (viewport-scroll-to-top model) '())]
       
       ;; G - vim bottom
       [(and (not (set-member? mods 'ctrl)) (equal? rune #\G))
        (values (viewport-scroll-to-bottom model) '())]
       
       ;; Ctrl+D - half page down
       [(and (set-member? mods 'ctrl) (equal? rune #\d))
        (define half-page (max 1 (quotient (viewport-model-height model) 2)))
        (values (scroll-by model 0 half-page) '())]
       
       ;; Ctrl+U - half page up
       [(and (set-member? mods 'ctrl) (equal? rune #\u))
        (define half-page (max 1 (quotient (viewport-model-height model) 2)))
        (values (scroll-by model 0 (- half-page)) '())]
       
       [else (values model '())])]
    
    [(mouse-event x y button action mods)
     (cond
       [(eq? button 'scroll-up)
        (values (scroll-by model 0 -3) '())]
       [(eq? button 'scroll-down)
        (values (scroll-by model 0 3) '())]
       [else (values model '())])]
    
    [_ (values model '())]))

(define (scroll-by model dx dy)
  (define content (viewport-model-content model))
  (define width (viewport-model-width model))
  (define height (viewport-model-height model))
  (define scroll-x (viewport-model-scroll-x model))
  (define scroll-y (viewport-model-scroll-y model))
  
  (define content-str (if (string? content) content (doc->string content)))
  (define lines (split-lines content-str))
  (define content-height (length lines))
  (define content-width (apply max 0 (map text-width lines)))
  
  (define max-scroll-y (max 0 (- content-height height)))
  (define max-scroll-x (max 0 (- content-width width)))
  
  (define new-scroll-y (max 0 (min max-scroll-y (+ scroll-y dy))))
  (define new-scroll-x (max 0 (min max-scroll-x (+ scroll-x dx))))
  
  (struct-copy viewport-model model
               [scroll-x new-scroll-x]
               [scroll-y new-scroll-y]))

(define (doc->string d)
  (match d
    [(doc-text content _) content]
    [(doc-block child _) (doc->string child)]
    [(doc-row children _) (string-join (map doc->string children) "")]
    [(doc-col children _) (string-join (map doc->string children) "\n")]
    [(doc-spacer w h _) (make-string (or w 0) #\space)]
    [(doc-overlay children) (if (null? children) "" (doc->string (car children)))]
    [(doc-empty) ""]
    [(? string?) d]
    [_ ""]))

;; ============================================================================
;; Content Management
;; ============================================================================

(define (viewport-set-content model content)
  (struct-copy viewport-model model [content content]))

(define (viewport-scroll-to model x y)
  (define content (viewport-model-content model))
  (define width (viewport-model-width model))
  (define height (viewport-model-height model))
  
  (define content-str (if (string? content) content (doc->string content)))
  (define lines (split-lines content-str))
  (define content-height (length lines))
  (define content-width (apply max 0 (map text-width lines)))
  
  (define max-scroll-y (max 0 (- content-height height)))
  (define max-scroll-x (max 0 (- content-width width)))
  
  (struct-copy viewport-model model
               [scroll-x (max 0 (min max-scroll-x x))]
               [scroll-y (max 0 (min max-scroll-y y))]))

(define (viewport-scroll-to-bottom model)
  (define content (viewport-model-content model))
  (define height (viewport-model-height model))
  
  (define content-str (if (string? content) content (doc->string content)))
  (define lines (split-lines content-str))
  (define content-height (length lines))
  (define max-scroll-y (max 0 (- content-height height)))
  
  (struct-copy viewport-model model
               [scroll-y max-scroll-y]))

(define (viewport-scroll-to-top model)
  (struct-copy viewport-model model
               [scroll-x 0]
               [scroll-y 0]))

;; ============================================================================
;; View
;; ============================================================================

(define (viewport-view model)
  (define content (viewport-model-content model))
  (define width (viewport-model-width model))
  (define height (viewport-model-height model))
  (define scroll-x (viewport-model-scroll-x model))
  (define scroll-y (viewport-model-scroll-y model))
  (define show-indicators? (viewport-model-show-indicators? model))
  (define style (viewport-model-style model))
  
  (define content-str (if (string? content) content (doc->string content)))
  (define all-lines (split-lines content-str))
  (define content-height (length all-lines))
  
  (define has-content-above? (> scroll-y 0))
  (define has-content-below? (< scroll-y (max 0 (- content-height height))))
  
  (define indicator-width (if show-indicators? 1 0))
  (define content-width (- width indicator-width))
  
  (define visible-lines
    (for/list ([i (in-range height)])
      (define line-idx (+ scroll-y i))
      (define line-content
        (if (< line-idx content-height)
            (list-ref all-lines line-idx)
            ""))
      (define scrolled
        (if (> scroll-x 0)
            (visible-slice line-content scroll-x)
            line-content))
      (define clipped
        (if (> (text-width scrolled) content-width)
            (visible-slice scrolled 0 content-width)
            (pad-right scrolled content-width)))
      clipped))
  
  (define lines-with-indicators
    (if show-indicators?
        (for/list ([line (in-list visible-lines)]
                   [i (in-naturals)])
          (define indicator
            (cond
              [(and (= i 0) has-content-above?) "▲"]
              [(and (= i (sub1 height)) has-content-below?) "▼"]
              [else " "]))
          (string-append line indicator))
        visible-lines))
  
  (with-style
   (vjoin (map txt lines-with-indicators))
   style))

;; ============================================================================
;; Queries
;; ============================================================================

(define (viewport-at-top? model)
  (= (viewport-model-scroll-y model) 0))

(define (viewport-at-bottom? model)
  (define content (viewport-model-content model))
  (define height (viewport-model-height model))
  (define scroll-y (viewport-model-scroll-y model))
  
  (define content-str (if (string? content) content (doc->string content)))
  (define content-height (length (split-lines content-str)))
  (define max-scroll (max 0 (- content-height height)))
  
  (>= scroll-y max-scroll))

(define (viewport-scroll-percent model)
  (define content (viewport-model-content model))
  (define height (viewport-model-height model))
  (define scroll-y (viewport-model-scroll-y model))
  
  (define content-str (if (string? content) content (doc->string content)))
  (define content-height (length (split-lines content-str)))
  (define max-scroll (max 1 (- content-height height)))
  
  (if (<= content-height height)
      1.0
      (/ scroll-y max-scroll)))

(define (viewport-content-height model)
  (define content (viewport-model-content model))
  (define content-str (if (string? content) content (doc->string content)))
  (length (split-lines content-str)))

(define (viewport-visible-lines model)
  (min (viewport-model-height model)
       (viewport-content-height model)))

;; ============================================================================
;; Tests
;; ============================================================================

(module+ test
  (require rackunit)
  
  (test-case "viewport-init creates model"
    (define model (viewport-init #:width 40 #:height 10))
    (check-equal? (viewport-model-width model) 40)
    (check-equal? (viewport-model-height model) 10)
    (check-equal? (viewport-model-scroll-x model) 0)
    (check-equal? (viewport-model-scroll-y model) 0))
  
  (test-case "viewport-init with content"
    (define model (viewport-init #:content "hello\nworld"))
    (check-equal? (viewport-content-height model) 2))
  
  (test-case "viewport-set-content"
    (define model (viewport-init))
    (define updated (viewport-set-content model "new\ncontent\nhere"))
    (check-equal? (viewport-content-height updated) 3))
  
  (test-case "scroll-by respects bounds"
    (define model (viewport-init #:height 2 #:content "1\n2\n3\n4\n5"))
    (define scrolled (scroll-by model 0 10))
    (check-equal? (viewport-model-scroll-y scrolled) 3)
    (define scrolled-back (scroll-by scrolled 0 -10))
    (check-equal? (viewport-model-scroll-y scrolled-back) 0))
  
  (test-case "viewport-scroll-to"
    (define model (viewport-init #:height 2 #:content "1\n2\n3\n4\n5"))
    (define scrolled (viewport-scroll-to model 0 2))
    (check-equal? (viewport-model-scroll-y scrolled) 2))
  
  (test-case "viewport-scroll-to-bottom"
    (define model (viewport-init #:height 2 #:content "1\n2\n3\n4\n5"))
    (define scrolled (viewport-scroll-to-bottom model))
    (check-equal? (viewport-model-scroll-y scrolled) 3))
  
  (test-case "viewport-scroll-to-top"
    (define model (viewport-init #:height 2 #:content "1\n2\n3\n4\n5"))
    (define scrolled (viewport-scroll-to model 0 2))
    (define at-top (viewport-scroll-to-top scrolled))
    (check-equal? (viewport-model-scroll-y at-top) 0))
  
  (test-case "viewport-at-top?"
    (define model (viewport-init #:height 2 #:content "1\n2\n3\n4\n5"))
    (check-true (viewport-at-top? model))
    (define scrolled (scroll-by model 0 1))
    (check-false (viewport-at-top? scrolled)))
  
  (test-case "viewport-at-bottom?"
    (define model (viewport-init #:height 2 #:content "1\n2\n3"))
    (check-false (viewport-at-bottom? model))
    (define scrolled (viewport-scroll-to-bottom model))
    (check-true (viewport-at-bottom? scrolled)))
  
  (test-case "viewport-scroll-percent"
    (define model (viewport-init #:height 2 #:content "1\n2\n3\n4\n5"))
    (check-equal? (viewport-scroll-percent model) 0)
    (define at-bottom (viewport-scroll-to-bottom model))
    (check-equal? (viewport-scroll-percent at-bottom) 1))
  
  (test-case "viewport-content-height"
    (define model (viewport-init #:content "a\nb\nc\nd"))
    (check-equal? (viewport-content-height model) 4))
  
  (test-case "viewport-visible-lines"
    (define model (viewport-init #:height 10 #:content "a\nb\nc"))
    (check-equal? (viewport-visible-lines model) 3)
    (define big-content (viewport-init #:height 3 #:content "1\n2\n3\n4\n5"))
    (check-equal? (viewport-visible-lines big-content) 3))
  
  (test-case "update with down arrow"
    (define model (viewport-init #:height 2 #:content "1\n2\n3\n4"))
    (define-values (updated _) (viewport-update model (key-event 'down #f (set) #"")))
    (check-equal? (viewport-model-scroll-y updated) 1))
  
  (test-case "update with up arrow"
    (define model (viewport-init #:height 2 #:content "1\n2\n3\n4"))
    (define scrolled (scroll-by model 0 2))
    (define-values (updated _) (viewport-update scrolled (key-event 'up #f (set) #"")))
    (check-equal? (viewport-model-scroll-y updated) 1))
  
  (test-case "update with page-up"
    (define model (viewport-init #:height 3 #:content "1\n2\n3\n4\n5\n6\n7\n8"))
    (define scrolled (scroll-by model 0 5))
    (define-values (updated _) (viewport-update scrolled (key-event 'page-up #f (set) #"")))
    (check-true (< (viewport-model-scroll-y updated) 5)))
  
  (test-case "update with page-down"
    (define model (viewport-init #:height 3 #:content "1\n2\n3\n4\n5\n6\n7\n8"))
    (define-values (updated _) (viewport-update model (key-event 'page-down #f (set) #"")))
    (check-true (> (viewport-model-scroll-y updated) 0)))
  
  (test-case "update with home"
    (define model (viewport-init #:height 2 #:content "1\n2\n3\n4"))
    (define scrolled (scroll-by model 0 2))
    (define-values (updated _) (viewport-update scrolled (key-event 'home #f (set) #"")))
    (check-equal? (viewport-model-scroll-y updated) 0))
  
  (test-case "update with end"
    (define model (viewport-init #:height 2 #:content "1\n2\n3\n4"))
    (define-values (updated _) (viewport-update model (key-event 'end #f (set) #"")))
    (check-true (viewport-at-bottom? updated)))
  
  (test-case "update with vim keys"
    (define model (viewport-init #:height 2 #:content "1\n2\n3\n4"))
    (define-values (down _) (viewport-update model (key-event #f #\j (set) #"")))
    (check-equal? (viewport-model-scroll-y down) 1)
    (define-values (up _2) (viewport-update down (key-event #f #\k (set) #"")))
    (check-equal? (viewport-model-scroll-y up) 0))
  
  (test-case "update with mouse wheel"
    (define model (viewport-init #:height 2 #:content "1\n2\n3\n4\n5\n6\n7\n8\n9\n10"))
    (define-values (down _) (viewport-update model (mouse-event 0 0 'scroll-down 'press (set))))
    (check-true (> (viewport-model-scroll-y down) 0))
    (define-values (up _2) (viewport-update down (mouse-event 0 0 'scroll-up 'press (set))))
    (check-true (< (viewport-model-scroll-y up) (viewport-model-scroll-y down))))
  
  (test-case "view returns doc"
    (define model (viewport-init #:content "hello\nworld" #:width 20 #:height 5))
    (define view (viewport-view model))
    (check-true (doc? view)))
  
  (test-case "view shows scroll indicators"
    (define model (viewport-init #:height 2 #:width 10
                                  #:content "1\n2\n3\n4\n5"
                                  #:show-indicators? #t))
    (define scrolled (scroll-by model 0 1))
    (define view (viewport-view scrolled))
    (check-true (doc? view)))
  
  (test-case "horizontal scrolling"
    (define model (viewport-init #:width 5 #:height 2 
                                  #:content "this is a long line\nshort"))
    (define scrolled (scroll-by model 5 0))
    (check-equal? (viewport-model-scroll-x scrolled) 5))
  
  (test-case "ctrl+d half page down"
    (define model (viewport-init #:height 4 #:content "1\n2\n3\n4\n5\n6\n7\n8"))
    (define-values (updated _) (viewport-update model (key-event #f #\d (set 'ctrl) #"")))
    (check-equal? (viewport-model-scroll-y updated) 2))
  
  (test-case "ctrl+u half page up"
    (define model (viewport-init #:height 4 #:content "1\n2\n3\n4\n5\n6\n7\n8"))
    (define scrolled (scroll-by model 0 4))
    (define-values (updated _) (viewport-update scrolled (key-event #f #\u (set 'ctrl) #"")))
    (check-equal? (viewport-model-scroll-y updated) 2)))
