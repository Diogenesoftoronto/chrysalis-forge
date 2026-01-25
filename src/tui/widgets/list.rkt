#lang racket/base

(require racket/match
         racket/string
         racket/set
         racket/list
         "../event.rkt"
         "../doc.rkt"
         "../style.rkt"
         "../text/measure.rkt")

(provide (struct-out list-model)
         (struct-out list-item)
         (struct-out list-styles)
         
         ;; Messages
         (struct-out list-focus-msg)
         (struct-out list-blur-msg)
         (struct-out list-select-msg)
         (struct-out list-selected-msg)
         
         ;; Init/Update/View
         list-init
         list-update
         list-view
         
         ;; Item management
         list-set-items
         list-add-item
         list-remove-item
         list-clear-filter
         
         ;; Queries
         list-selected-item
         list-selected-index
         list-visible-items
         list-is-empty?)

;; ============================================================================
;; Styles
;; ============================================================================

(struct list-styles (normal selected focused-normal focused-selected disabled filtered)
  #:transparent)

(define default-styles
  (list-styles
   empty-style
   (style-set empty-style #:reverse #t)
   empty-style
   (style-set empty-style #:reverse #t #:bold #t)
   (style-set empty-style #:dim #t)
   (style-set empty-style #:fg 'yellow)))

;; ============================================================================
;; List Item
;; ============================================================================

(struct list-item (value display-text enabled? metadata)
  #:transparent)

(define (make-list-item value
                        #:display-text [display-text #f]
                        #:enabled? [enabled? #t]
                        #:metadata [metadata #f])
  (list-item value
             (or display-text (if (string? value) value (format "~a" value)))
             enabled?
             metadata))

;; ============================================================================
;; Model
;; ============================================================================

(struct list-model
  (items selected-index focused? filter-text height scroll-offset styles filtering?)
  #:transparent)

(define (list-init #:items [items '()]
                   #:height [height 10]
                   #:styles [styles default-styles]
                   #:filtering? [filtering? #f])
  (define normalized-items
    (for/list ([item (in-list items)])
      (if (list-item? item)
          item
          (make-list-item item))))
  (define initial-index
    (if (null? normalized-items)
        #f
        (find-first-enabled normalized-items 0 1)))
  (list-model
   normalized-items
   initial-index
   #f
   ""
   height
   0
   styles
   filtering?))

(define (find-first-enabled items start-index direction)
  (define len (length items))
  (if (= len 0)
      #f
      (let loop ([i start-index])
        (cond
          [(< i 0) #f]
          [(>= i len) #f]
          [(list-item-enabled? (list-ref items i)) i]
          [else (loop (+ i direction))]))))

;; ============================================================================
;; Messages
;; ============================================================================

(struct list-focus-msg () #:transparent)
(struct list-blur-msg () #:transparent)
(struct list-select-msg (index) #:transparent)
(struct list-selected-msg (item) #:transparent)

;; ============================================================================
;; Update
;; ============================================================================

(define (list-update model evt)
  (match evt
    [(list-focus-msg)
     (values (struct-copy list-model model [focused? #t]) '())]
    
    [(list-blur-msg)
     (values (struct-copy list-model model [focused? #f]) '())]
    
    [(list-select-msg index)
     (define items (get-visible-items model))
     (if (and index (< index (length items)))
         (let ([item (list-ref items index)])
           (if (list-item-enabled? item)
               (values (struct-copy list-model model [selected-index index])
                       '())
               (values model '())))
         (values model '()))]
    
    [(key-event key rune mods _)
     (cond
       [(not (list-model-focused? model))
        (values model '())]
       
       ;; Up arrow or k
       [(or (eq? key 'up) (equal? rune #\k))
        (handle-move-up model)]
       
       ;; Down arrow or j
       [(or (eq? key 'down) (equal? rune #\j))
        (handle-move-down model)]
       
       ;; Page up
       [(eq? key 'page-up)
        (handle-page-up model)]
       
       ;; Page down
       [(eq? key 'page-down)
        (handle-page-down model)]
       
       ;; Home
       [(eq? key 'home)
        (handle-home model)]
       
       ;; End
       [(eq? key 'end)
        (handle-end model)]
       
       ;; Enter - select
       [(eq? key 'enter)
        (handle-enter model)]
       
       ;; Escape - blur or clear filter
       [(eq? key 'esc)
        (if (and (list-model-filtering? model)
                 (not (string=? (list-model-filter-text model) "")))
            (values (list-clear-filter model) '())
            (values (struct-copy list-model model [focused? #f]) '()))]
       
       ;; Backspace - remove filter char
       [(eq? key 'backspace)
        (if (list-model-filtering? model)
            (handle-filter-backspace model)
            (values model '()))]
       
       ;; Character input for filtering
       [(and (list-model-filtering? model)
             rune
             (char-graphic? rune))
        (handle-filter-input model rune)]
       
       ;; Space for filtering
       [(and (list-model-filtering? model)
             (eq? key 'space))
        (handle-filter-input model #\space)]
       
       [else (values model '())])]
    
    [_ (values model '())]))

(define (handle-move-up model)
  (define items (get-visible-items model))
  (define current (list-model-selected-index model))
  (cond
    [(null? items) (values model '())]
    [(not current) (values model '())]
    [else
     (define new-index (find-first-enabled items (sub1 current) -1))
     (if new-index
         (values (ensure-visible (struct-copy list-model model [selected-index new-index]))
                 '())
         (values model '()))]))

(define (handle-move-down model)
  (define items (get-visible-items model))
  (define current (list-model-selected-index model))
  (cond
    [(null? items) (values model '())]
    [(not current)
     (define first-idx (find-first-enabled items 0 1))
     (if first-idx
         (values (ensure-visible (struct-copy list-model model [selected-index first-idx]))
                 '())
         (values model '()))]
    [else
     (define new-index (find-first-enabled items (add1 current) 1))
     (if new-index
         (values (ensure-visible (struct-copy list-model model [selected-index new-index]))
                 '())
         (values model '()))]))

(define (handle-page-up model)
  (define items (get-visible-items model))
  (define current (or (list-model-selected-index model) 0))
  (define height (list-model-height model))
  (define target (max 0 (- current (sub1 height))))
  (define new-index (find-first-enabled items target 1))
  (if new-index
      (values (ensure-visible (struct-copy list-model model [selected-index new-index]))
              '())
      (values model '())))

(define (handle-page-down model)
  (define items (get-visible-items model))
  (define current (or (list-model-selected-index model) 0))
  (define height (list-model-height model))
  (define target (min (sub1 (length items)) (+ current (sub1 height))))
  (define new-index (find-first-enabled items target -1))
  (if new-index
      (values (ensure-visible (struct-copy list-model model [selected-index new-index]))
              '())
      (values model '())))

(define (handle-home model)
  (define items (get-visible-items model))
  (define new-index (find-first-enabled items 0 1))
  (if new-index
      (values (struct-copy list-model model
                           [selected-index new-index]
                           [scroll-offset 0])
              '())
      (values model '())))

(define (handle-end model)
  (define items (get-visible-items model))
  (define new-index (find-first-enabled items (sub1 (length items)) -1))
  (if new-index
      (let* ([height (list-model-height model)]
             [max-scroll (max 0 (- (length items) height))])
        (values (struct-copy list-model model
                             [selected-index new-index]
                             [scroll-offset max-scroll])
                '()))
      (values model '())))

(define (handle-enter model)
  (define items (get-visible-items model))
  (define index (list-model-selected-index model))
  (if (and index (< index (length items)))
      (let ([item (list-ref items index)])
        (if (list-item-enabled? item)
            (values model (list (list-selected-msg item)))
            (values model '())))
      (values model '())))

(define (handle-filter-input model char)
  (define new-filter (string-append (list-model-filter-text model) (string char)))
  (define new-model (struct-copy list-model model [filter-text new-filter]))
  (define visible (get-visible-items new-model))
  (define new-index
    (if (null? visible)
        #f
        (or (find-first-enabled visible 0 1) #f)))
  (values (struct-copy list-model new-model
                       [selected-index new-index]
                       [scroll-offset 0])
          '()))

(define (handle-filter-backspace model)
  (define filter (list-model-filter-text model))
  (if (string=? filter "")
      (values model '())
      (let* ([new-filter (substring filter 0 (sub1 (string-length filter)))]
             [new-model (struct-copy list-model model [filter-text new-filter])]
             [visible (get-visible-items new-model)]
             [new-index (if (null? visible)
                            #f
                            (or (find-first-enabled visible 0 1) #f))])
        (values (struct-copy list-model new-model
                             [selected-index new-index]
                             [scroll-offset 0])
                '()))))

(define (ensure-visible model)
  (define index (list-model-selected-index model))
  (define height (list-model-height model))
  (define scroll (list-model-scroll-offset model))
  (cond
    [(not index) model]
    [(< index scroll)
     (struct-copy list-model model [scroll-offset index])]
    [(>= index (+ scroll height))
     (struct-copy list-model model [scroll-offset (- index (sub1 height))])]
    [else model]))

;; ============================================================================
;; Item Management
;; ============================================================================

(define (list-set-items model items)
  (define normalized
    (for/list ([item (in-list items)])
      (if (list-item? item)
          item
          (make-list-item item))))
  (define new-index
    (if (null? normalized)
        #f
        (find-first-enabled normalized 0 1)))
  (struct-copy list-model model
               [items normalized]
               [selected-index new-index]
               [scroll-offset 0]
               [filter-text ""]))

(define (list-add-item model item)
  (define new-item (if (list-item? item) item (make-list-item item)))
  (define new-items (append (list-model-items model) (list new-item)))
  (define current-index (list-model-selected-index model))
  (struct-copy list-model model
               [items new-items]
               [selected-index (or current-index
                                    (if (list-item-enabled? new-item)
                                        (sub1 (length new-items))
                                        #f))]))

(define (list-remove-item model index)
  (define items (list-model-items model))
  (if (or (< index 0) (>= index (length items)))
      model
      (let* ([new-items (append (take items index) (drop items (add1 index)))]
             [current (list-model-selected-index model)]
             [new-index
              (cond
                [(null? new-items) #f]
                [(not current) #f]
                [(< current index) current]
                [(= current index)
                 (or (find-first-enabled new-items (min current (sub1 (length new-items))) 1)
                     (find-first-enabled new-items (min current (sub1 (length new-items))) -1))]
                [else (sub1 current)])])
        (struct-copy list-model model
                     [items new-items]
                     [selected-index new-index]))))

(define (list-clear-filter model)
  (define visible-before (get-visible-items model))
  (define selected-item
    (let ([idx (list-model-selected-index model)])
      (and idx (< idx (length visible-before))
           (list-ref visible-before idx))))
  (define new-model (struct-copy list-model model [filter-text ""]))
  (define all-items (list-model-items new-model))
  (define new-index
    (if selected-item
        (for/first ([item (in-list all-items)]
                    [i (in-naturals)]
                    #:when (equal? (list-item-value item)
                                   (list-item-value selected-item)))
          i)
        (find-first-enabled all-items 0 1)))
  (ensure-visible (struct-copy list-model new-model [selected-index new-index])))

;; ============================================================================
;; View
;; ============================================================================

(define (list-view model [size #f])
  (define width (and size (car size)))
  (define height (or (and size (cdr size)) (list-model-height model)))
  (define items (get-visible-items model))
  (define scroll (list-model-scroll-offset model))
  (define selected (list-model-selected-index model))
  (define focused? (list-model-focused? model))
  (define styles (list-model-styles model))
  (define filter-text (list-model-filter-text model))
  (define filtering? (list-model-filtering? model))
  
  (define visible-items
    (for/list ([i (in-range height)])
      (define item-idx (+ scroll i))
      (cond
        [(>= item-idx (length items))
         (make-empty-row width)]
        [else
         (define item (list-ref items item-idx))
         (define is-selected? (and selected (= item-idx selected)))
         (define item-style
           (cond
             [(not (list-item-enabled? item))
              (list-styles-disabled styles)]
             [(and focused? is-selected?)
              (list-styles-focused-selected styles)]
             [is-selected?
              (list-styles-selected styles)]
             [focused?
              (list-styles-focused-normal styles)]
             [else
              (list-styles-normal styles)]))
         (define text (list-item-display-text item))
         (define display-text
           (if width
               (if (> (text-width text) width)
                   (truncate-text text width)
                   (pad-right text width))
               text))
         (define highlighted
           (if (and filtering? (not (string=? filter-text "")))
               (highlight-filter display-text filter-text styles)
               (txt display-text)))
         (with-style highlighted item-style)])))
  
  (vjoin visible-items))

(define (make-empty-row width)
  (if width
      (txt (make-string width #\space))
      (txt "")))

(define (highlight-filter text filter-text styles)
  (define filter-lower (string-downcase filter-text))
  (define text-lower (string-downcase text))
  (define match-pos (string-contains? text-lower filter-lower))
  (if match-pos
      (let* ([before (substring text 0 match-pos)]
             [match (substring text match-pos (+ match-pos (string-length filter-text)))]
             [after (substring text (+ match-pos (string-length filter-text)))])
        (row (txt before)
             (with-style (txt match) (list-styles-filtered styles))
             (txt after)))
      (txt text)))

(define (string-contains? str substr)
  (define pos (string-index-of str substr))
  pos)

(define (string-index-of str substr)
  (define str-len (string-length str))
  (define sub-len (string-length substr))
  (if (> sub-len str-len)
      #f
      (for/first ([i (in-range (add1 (- str-len sub-len)))]
                  #:when (string=? (substring str i (+ i sub-len)) substr))
        i)))

;; ============================================================================
;; Queries
;; ============================================================================

(define (get-visible-items model)
  (define items (list-model-items model))
  (define filter-text (list-model-filter-text model))
  (if (string=? filter-text "")
      items
      (filter (λ (item)
                (string-contains?
                 (string-downcase (list-item-display-text item))
                 (string-downcase filter-text)))
              items)))

(define (list-selected-item model)
  (define items (get-visible-items model))
  (define index (list-model-selected-index model))
  (if (and index (< index (length items)))
      (list-ref items index)
      #f))

(define (list-selected-index model)
  (list-model-selected-index model))

(define (list-visible-items model)
  (get-visible-items model))

(define (list-is-empty? model)
  (null? (list-model-items model)))

;; ============================================================================
;; Tests
;; ============================================================================

(module+ test
  (require rackunit)
  
  (test-case "list-init creates model"
    (define model (list-init #:items '("a" "b" "c")))
    (check-equal? (length (list-model-items model)) 3)
    (check-equal? (list-selected-index model) 0)
    (check-false (list-model-focused? model)))
  
  (test-case "list-init with empty items"
    (define model (list-init #:items '()))
    (check-true (list-is-empty? model))
    (check-false (list-selected-item model)))
  
  (test-case "list-init with list-items"
    (define items (list (make-list-item "a")
                        (make-list-item "b" #:enabled? #f)
                        (make-list-item "c")))
    (define model (list-init #:items items))
    (check-equal? (list-selected-index model) 0))
  
  (test-case "focus and blur"
    (define model (list-init #:items '("a")))
    (define-values (focused _) (list-update model (list-focus-msg)))
    (check-true (list-model-focused? focused))
    (define-values (blurred _2) (list-update focused (list-blur-msg)))
    (check-false (list-model-focused? blurred)))
  
  (test-case "move down"
    (define model (list-init #:items '("a" "b" "c")))
    (define-values (focused _) (list-update model (list-focus-msg)))
    (define-values (moved _2) (list-update focused (key-event 'down #f (set) #"")))
    (check-equal? (list-selected-index moved) 1))
  
  (test-case "move up"
    (define model (list-init #:items '("a" "b" "c")))
    (define moved (struct-copy list-model model [selected-index 2] [focused? #t]))
    (define-values (after _) (list-update moved (key-event 'up #f (set) #"")))
    (check-equal? (list-selected-index after) 1))
  
  (test-case "vim keys j and k"
    (define model (list-init #:items '("a" "b" "c")))
    (define-values (focused _) (list-update model (list-focus-msg)))
    (define-values (down _2) (list-update focused (key-event #f #\j (set) #"")))
    (check-equal? (list-selected-index down) 1)
    (define-values (up _3) (list-update down (key-event #f #\k (set) #"")))
    (check-equal? (list-selected-index up) 0))
  
  (test-case "home and end"
    (define model (list-init #:items '("a" "b" "c" "d" "e")))
    (define-values (focused _) (list-update model (list-focus-msg)))
    (define-values (at-end _2) (list-update focused (key-event 'end #f (set) #"")))
    (check-equal? (list-selected-index at-end) 4)
    (define-values (at-home _3) (list-update at-end (key-event 'home #f (set) #"")))
    (check-equal? (list-selected-index at-home) 0))
  
  (test-case "page up and down"
    (define model (list-init #:items '("a" "b" "c" "d" "e" "f" "g" "h") #:height 3))
    (define at-bottom (struct-copy list-model model [selected-index 7] [focused? #t]))
    (define-values (page-up _) (list-update at-bottom (key-event 'page-up #f (set) #"")))
    (check-true (< (list-selected-index page-up) 7))
    (define-values (page-down _2) (list-update page-up (key-event 'page-down #f (set) #"")))
    (check-true (> (list-selected-index page-down) (list-selected-index page-up))))
  
  (test-case "enter selects item"
    (define model (list-init #:items '("a" "b" "c")))
    (define focused (struct-copy list-model model [focused? #t] [selected-index 1]))
    (define-values (after cmds) (list-update focused (key-event 'enter #f (set) #"")))
    (check-equal? (length cmds) 1)
    (check-pred list-selected-msg? (car cmds))
    (check-equal? (list-item-value (list-selected-msg-item (car cmds))) "b"))
  
  (test-case "skip disabled items"
    (define items (list (make-list-item "a")
                        (make-list-item "b" #:enabled? #f)
                        (make-list-item "c")))
    (define model (list-init #:items items))
    (define-values (focused _) (list-update model (list-focus-msg)))
    (define-values (moved _2) (list-update focused (key-event 'down #f (set) #"")))
    (check-equal? (list-selected-index moved) 2))
  
  (test-case "filtering"
    (define model (list-init #:items '("apple" "banana" "cherry") #:filtering? #t))
    (define-values (focused _) (list-update model (list-focus-msg)))
    (define-values (filtered _2) (list-update focused (key-event #f #\a (set) #"")))
    (check-equal? (list-model-filter-text filtered) "a")
    (check-equal? (length (list-visible-items filtered)) 2))
  
  (test-case "filter backspace"
    (define model (list-init #:items '("apple" "banana") #:filtering? #t))
    (define with-filter (struct-copy list-model model [filter-text "app"] [focused? #t]))
    (define-values (after _) (list-update with-filter (key-event 'backspace #f (set) #"")))
    (check-equal? (list-model-filter-text after) "ap"))
  
  (test-case "clear filter on escape"
    (define model (list-init #:items '("apple" "banana") #:filtering? #t))
    (define with-filter (struct-copy list-model model [filter-text "app"] [focused? #t]))
    (define-values (after _) (list-update with-filter (key-event 'esc #f (set) #"")))
    (check-equal? (list-model-filter-text after) ""))
  
  (test-case "list-set-items"
    (define model (list-init #:items '("a" "b")))
    (define updated (list-set-items model '("x" "y" "z")))
    (check-equal? (length (list-model-items updated)) 3)
    (check-equal? (list-selected-index updated) 0))
  
  (test-case "list-add-item"
    (define model (list-init #:items '("a" "b")))
    (define updated (list-add-item model "c"))
    (check-equal? (length (list-model-items updated)) 3))
  
  (test-case "list-remove-item"
    (define model (list-init #:items '("a" "b" "c")))
    (define selected-b (struct-copy list-model model [selected-index 1]))
    (define after-remove (list-remove-item selected-b 1))
    (check-equal? (length (list-model-items after-remove)) 2)
    (check-true (or (not (list-selected-index after-remove))
                    (< (list-selected-index after-remove) 2))))
  
  (test-case "list-selected-item"
    (define model (list-init #:items '("a" "b" "c")))
    (define selected (struct-copy list-model model [selected-index 1]))
    (check-equal? (list-item-value (list-selected-item selected)) "b"))
  
  (test-case "list-visible-items with filter"
    (define model (list-init #:items '("apple" "banana" "cherry")))
    (define filtered (struct-copy list-model model [filter-text "an"]))
    (check-equal? (length (list-visible-items filtered)) 1)
    (check-equal? (list-item-value (car (list-visible-items filtered))) "banana"))
  
  (test-case "view returns doc"
    (define model (list-init #:items '("a" "b" "c") #:height 5))
    (define view (list-view model))
    (check-true (doc? view)))
  
  (test-case "ensure-visible scrolls"
    (define model (list-init #:items '("a" "b" "c" "d" "e" "f") #:height 3))
    (define at-end (struct-copy list-model model [selected-index 5]))
    (define visible (ensure-visible at-end))
    (check-true (<= (list-model-scroll-offset visible) 5))
    (check-true (>= (+ (list-model-scroll-offset visible) 3) 6)))
  
  (test-case "list with metadata"
    (define items (list (make-list-item "item1" #:metadata '((id . 1)))
                        (make-list-item "item2" #:metadata '((id . 2)))))
    (define model (list-init #:items items))
    (define item (list-selected-item model))
    (check-equal? (list-item-metadata item) '((id . 1)))))
