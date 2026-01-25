#lang racket/base

(require racket/match
         racket/string
         racket/set
         racket/list
         "../event.rkt"
         "../doc.rkt"
         "../style.rkt"
         "../text/buffer.rkt"
         "../text/measure.rkt")

(provide (struct-out textarea-model)
         (struct-out textarea-styles)
         
         ;; Messages
         (struct-out textarea-focus-msg)
         (struct-out textarea-blur-msg)
         (struct-out textarea-set-value-msg)
         (struct-out textarea-changed-msg)
         
         ;; Init/Update/View
         textarea-init
         textarea-update
         textarea-view
         
         ;; Queries
         textarea-value
         textarea-focused?
         textarea-cursor-position
         textarea-line-count)

;; ============================================================================
;; Styles
;; ============================================================================

(struct textarea-styles (normal focused placeholder cursor line-number gutter)
  #:transparent)

(define default-styles
  (textarea-styles
   empty-style
   empty-style
   (style-set empty-style #:dim #t)
   "│"
   (style-set empty-style #:dim #t)
   (style-set empty-style #:dim #t)))

;; ============================================================================
;; Model
;; ============================================================================

(struct textarea-model
  (buffer placeholder focused? width height scroll-offset
   cursor-visible-row line-numbers? soft-wrap? max-lines styles)
  #:transparent)

(define (textarea-init #:placeholder [placeholder ""]
                       #:width [width 40]
                       #:height [height 5]
                       #:line-numbers? [line-numbers? #f]
                       #:soft-wrap? [soft-wrap? #t]
                       #:max-lines [max-lines #f]
                       #:styles [styles default-styles]
                       #:initial-value [initial-value ""])
  (textarea-model
   (make-buffer initial-value)
   placeholder
   #f
   width
   height
   0
   0
   line-numbers?
   soft-wrap?
   max-lines
   styles))

;; ============================================================================
;; Messages
;; ============================================================================

(struct textarea-focus-msg () #:transparent)
(struct textarea-blur-msg () #:transparent)
(struct textarea-set-value-msg (value) #:transparent)
(struct textarea-changed-msg (value) #:transparent)

;; ============================================================================
;; Update
;; ============================================================================

(define (textarea-update model evt)
  (match evt
    [(textarea-focus-msg)
     (values (struct-copy textarea-model model [focused? #t]) '())]
    
    [(textarea-blur-msg)
     (values (struct-copy textarea-model model [focused? #f]) '())]
    
    [(textarea-set-value-msg value)
     (define new-buf (make-buffer value))
     (define new-model (ensure-cursor-visible
                        (struct-copy textarea-model model [buffer new-buf])))
     (values new-model (list (textarea-changed-msg value)))]
    
    [(key-event key rune mods _)
     (cond
       [(not (textarea-model-focused? model))
        (values model '())]
       
       ;; Enter - new line
       [(eq? key 'enter)
        (handle-newline model)]
       
       ;; Escape - blur
       [(eq? key 'esc)
        (values (struct-copy textarea-model model [focused? #f]) '())]
       
       ;; Backspace
       [(eq? key 'backspace)
        (handle-edit model buffer-delete-char)]
       
       ;; Delete
       [(eq? key 'delete)
        (handle-edit model buffer-delete-forward)]
       
       ;; Home
       [(eq? key 'home)
        (handle-cursor model buffer-move-home)]
       
       ;; End
       [(eq? key 'end)
        (handle-cursor model buffer-move-end)]
       
       ;; Left arrow
       [(eq? key 'left)
        (cond
          [(set-member? mods 'ctrl) (handle-cursor model buffer-move-word-left)]
          [else (handle-cursor model buffer-move-left)])]
       
       ;; Right arrow
       [(eq? key 'right)
        (cond
          [(set-member? mods 'ctrl) (handle-cursor model buffer-move-word-right)]
          [else (handle-cursor model buffer-move-right)])]
       
       ;; Up arrow
       [(eq? key 'up)
        (cond
          [(set-member? mods 'ctrl) (handle-scroll-up model)]
          [else (handle-cursor model buffer-move-up)])]
       
       ;; Down arrow
       [(eq? key 'down)
        (cond
          [(set-member? mods 'ctrl) (handle-scroll-down model)]
          [else (handle-cursor model buffer-move-down)])]
       
       ;; Page up
       [(eq? key 'page-up)
        (handle-page-up model)]
       
       ;; Page down
       [(eq? key 'page-down)
        (handle-page-down model)]
       
       ;; Ctrl+K - kill to end of line
       [(and (set-member? mods 'ctrl) (equal? rune #\k))
        (handle-edit model buffer-delete-to-end)]
       
       ;; Ctrl+U - kill to start of line
       [(and (set-member? mods 'ctrl) (equal? rune #\u))
        (handle-edit model buffer-delete-to-start)]
       
       ;; Ctrl+W - delete word backward
       [(and (set-member? mods 'ctrl) (equal? rune #\w))
        (handle-edit model buffer-delete-word)]
       
       ;; Ctrl+A - move to line start
       [(and (set-member? mods 'ctrl) (equal? rune #\a))
        (handle-cursor model buffer-move-home)]
       
       ;; Ctrl+E - move to line end
       [(and (set-member? mods 'ctrl) (equal? rune #\e))
        (handle-cursor model buffer-move-end)]
       
       ;; Ctrl+F - forward char
       [(and (set-member? mods 'ctrl) (equal? rune #\f))
        (handle-cursor model buffer-move-right)]
       
       ;; Ctrl+B - backward char
       [(and (set-member? mods 'ctrl) (equal? rune #\b))
        (handle-cursor model buffer-move-left)]
       
       ;; Ctrl+N - next line
       [(and (set-member? mods 'ctrl) (equal? rune #\n))
        (handle-cursor model buffer-move-down)]
       
       ;; Ctrl+P - previous line
       [(and (set-member? mods 'ctrl) (equal? rune #\p))
        (handle-cursor model buffer-move-up)]
       
       ;; Character input
       [(and rune (char-graphic? rune))
        (handle-char-input model rune)]
       
       ;; Space
       [(and (eq? key 'space) (not rune))
        (handle-char-input model #\space)]
       
       ;; Tab - insert spaces
       [(eq? key 'tab)
        (handle-tab model)]
       
       [else (values model '())])]
    
    [(paste-event text)
     (if (textarea-model-focused? model)
         (handle-paste model text)
         (values model '()))]
    
    [_ (values model '())]))

(define (handle-cursor model op)
  (define buf (textarea-model-buffer model))
  (define new-model (struct-copy textarea-model model [buffer (op buf)]))
  (values (ensure-cursor-visible new-model) '()))

(define (handle-edit model op)
  (define buf (textarea-model-buffer model))
  (define new-buf (op buf))
  (define new-model (ensure-cursor-visible
                     (struct-copy textarea-model model [buffer new-buf])))
  (values new-model (list (textarea-changed-msg (buffer-text new-buf)))))

(define (handle-newline model)
  (define max-lines (textarea-model-max-lines model))
  (define buf (textarea-model-buffer model))
  (define current-lines (buffer-line-count buf))
  (if (and max-lines (>= current-lines max-lines))
      (values model '())
      (handle-edit model (λ (b) (buffer-insert b "\n")))))

(define (handle-char-input model char)
  (define buf (textarea-model-buffer model))
  (define new-buf (buffer-insert buf (string char)))
  (define new-model (ensure-cursor-visible
                     (struct-copy textarea-model model [buffer new-buf])))
  (values new-model (list (textarea-changed-msg (buffer-text new-buf)))))

(define (handle-tab model)
  (define buf (textarea-model-buffer model))
  (define new-buf (buffer-insert buf "    "))
  (define new-model (ensure-cursor-visible
                     (struct-copy textarea-model model [buffer new-buf])))
  (values new-model (list (textarea-changed-msg (buffer-text new-buf)))))

(define (handle-paste model text)
  (define buf (textarea-model-buffer model))
  (define max-lines (textarea-model-max-lines model))
  (define text-to-insert
    (if max-lines
        (let* ([current-lines (buffer-line-count buf)]
               [paste-lines (length (split-lines text))]
               [allowed-lines (- max-lines current-lines)])
          (if (> paste-lines allowed-lines)
              (string-join (take (split-lines text) (max 1 (add1 allowed-lines))) "\n")
              text))
        text))
  (define new-buf (buffer-insert buf text-to-insert))
  (define new-model (ensure-cursor-visible
                     (struct-copy textarea-model model [buffer new-buf])))
  (values new-model (list (textarea-changed-msg (buffer-text new-buf)))))

(define (handle-scroll-up model)
  (define scroll (textarea-model-scroll-offset model))
  (define new-scroll (max 0 (sub1 scroll)))
  (values (struct-copy textarea-model model [scroll-offset new-scroll]) '()))

(define (handle-scroll-down model)
  (define scroll (textarea-model-scroll-offset model))
  (define buf (textarea-model-buffer model))
  (define max-scroll (max 0 (- (buffer-line-count buf) (textarea-model-height model))))
  (define new-scroll (min max-scroll (add1 scroll)))
  (values (struct-copy textarea-model model [scroll-offset new-scroll]) '()))

(define (handle-page-up model)
  (define scroll (textarea-model-scroll-offset model))
  (define height (textarea-model-height model))
  (define page-size (max 1 (sub1 height)))
  (define new-scroll (max 0 (- scroll page-size)))
  (define buf (textarea-model-buffer model))
  (define current-line (buffer-current-line buf))
  (define target-line (max 0 (- current-line page-size)))
  (define new-buf (move-to-line buf target-line))
  (values (ensure-cursor-visible
           (struct-copy textarea-model model
                        [buffer new-buf]
                        [scroll-offset new-scroll]))
          '()))

(define (handle-page-down model)
  (define scroll (textarea-model-scroll-offset model))
  (define height (textarea-model-height model))
  (define buf (textarea-model-buffer model))
  (define max-scroll (max 0 (- (buffer-line-count buf) height)))
  (define page-size (max 1 (sub1 height)))
  (define new-scroll (min max-scroll (+ scroll page-size)))
  (define current-line (buffer-current-line buf))
  (define max-line (sub1 (buffer-line-count buf)))
  (define target-line (min max-line (+ current-line page-size)))
  (define new-buf (move-to-line buf target-line))
  (values (ensure-cursor-visible
           (struct-copy textarea-model model
                        [buffer new-buf]
                        [scroll-offset new-scroll]))
          '()))

(define (move-to-line buf line)
  (define current-col (buffer-current-column buf))
  (define text (buffer-text buf))
  (define lines (split-lines text))
  (define target-line (min line (sub1 (max 1 (length lines)))))
  (define pos
    (let loop ([i 0] [pos 0])
      (cond
        [(= i target-line)
         (define line-len (if (< i (length lines))
                              (string-length (list-ref lines i))
                              0))
         (+ pos (min current-col line-len))]
        [(>= i (length lines)) pos]
        [else
         (loop (add1 i) (+ pos (string-length (list-ref lines i)) 1))])))
  (buffer-move-to buf pos))

(define (ensure-cursor-visible model)
  (define buf (textarea-model-buffer model))
  (define height (textarea-model-height model))
  (define scroll (textarea-model-scroll-offset model))
  (define cursor-line (buffer-current-line buf))
  (define visible-row (- cursor-line scroll))
  (cond
    [(< visible-row 0)
     (struct-copy textarea-model model
                  [scroll-offset cursor-line]
                  [cursor-visible-row 0])]
    [(>= visible-row height)
     (define new-scroll (- cursor-line (sub1 height)))
     (struct-copy textarea-model model
                  [scroll-offset new-scroll]
                  [cursor-visible-row (sub1 height)])]
    [else
     (struct-copy textarea-model model
                  [cursor-visible-row visible-row])]))

;; ============================================================================
;; View
;; ============================================================================

(define (textarea-view model [size #f])
  (define width (or (and size (car size)) (textarea-model-width model)))
  (define height (or (and size (cdr size)) (textarea-model-height model)))
  (define buf (textarea-model-buffer model))
  (define text (buffer-text buf))
  (define placeholder (textarea-model-placeholder model))
  (define focused? (textarea-model-focused? model))
  (define scroll (textarea-model-scroll-offset model))
  (define line-numbers? (textarea-model-line-numbers? model))
  (define soft-wrap? (textarea-model-soft-wrap? model))
  (define styles (textarea-model-styles model))
  (define cursor-char (textarea-styles-cursor styles))
  
  (define is-empty? (string=? text ""))
  (define display-text (if is-empty? placeholder text))
  
  (define all-lines (split-lines display-text))
  (define total-lines (length all-lines))
  
  (define gutter-width
    (if line-numbers?
        (+ 2 (string-length (number->string total-lines)))
        0))
  
  (define content-width (- width gutter-width))
  
  (define cursor-line (if is-empty? 0 (buffer-current-line buf)))
  (define cursor-col (if is-empty? 0 (buffer-current-column buf)))
  
  (define visible-lines
    (for/list ([i (in-range height)])
      (define line-idx (+ scroll i))
      (cond
        [(>= line-idx total-lines)
         (make-empty-line gutter-width content-width line-numbers? #f styles)]
        [else
         (define line-text (list-ref all-lines line-idx))
         (define is-cursor-line? (and focused? (not is-empty?) (= line-idx cursor-line)))
         (define line-with-cursor
           (if is-cursor-line?
               (insert-cursor-in-line line-text cursor-col cursor-char)
               line-text))
         (define display-line
           (if soft-wrap?
               (truncate-or-pad line-with-cursor content-width)
               (scroll-line-horizontal line-with-cursor content-width
                                       (if is-cursor-line? cursor-col 0))))
         (define gutter
           (if line-numbers?
               (format-gutter (add1 line-idx) gutter-width styles)
               ""))
         (string-append gutter display-line)])))
  
  (define base-style
    (if focused?
        (textarea-styles-focused styles)
        (textarea-styles-normal styles)))
  
  (define content-style
    (if is-empty?
        (textarea-styles-placeholder styles)
        base-style))
  
  (with-style
   (vjoin (map txt visible-lines))
   content-style))

(define (insert-cursor-in-line line col cursor-char)
  (define len (string-length line))
  (define pos (min col len))
  (string-append
   (substring line 0 pos)
   cursor-char
   (if (< pos len) (substring line pos) "")))

(define (truncate-or-pad line width)
  (define line-width (text-width line))
  (cond
    [(> line-width width)
     (visible-slice line 0 width)]
    [(< line-width width)
     (string-append line (make-string (- width line-width) #\space))]
    [else line]))

(define (scroll-line-horizontal line width cursor-col)
  (define line-width (text-width line))
  (cond
    [(<= line-width width)
     (pad-right line width)]
    [else
     (define half-width (quotient width 2))
     (define start (max 0 (- cursor-col half-width)))
     (define end (min line-width (+ start width)))
     (define adjusted-start (max 0 (- end width)))
     (pad-right (visible-slice line adjusted-start end) width)]))

(define (format-gutter line-num width styles)
  (define num-str (number->string line-num))
  (define padded (pad-left num-str (- width 1)))
  (string-append padded " "))

(define (make-empty-line gutter-width content-width line-numbers? line-num styles)
  (define gutter
    (if line-numbers?
        (if line-num
            (format-gutter line-num gutter-width styles)
            (make-string gutter-width #\space))
        ""))
  (string-append gutter (make-string content-width #\space)))

;; ============================================================================
;; Queries
;; ============================================================================

(define (textarea-value model)
  (buffer-text (textarea-model-buffer model)))

(define (textarea-focused? model)
  (textarea-model-focused? model))

(define (textarea-cursor-position model)
  (define buf (textarea-model-buffer model))
  (cons (buffer-current-line buf) (buffer-current-column buf)))

(define (textarea-line-count model)
  (buffer-line-count (textarea-model-buffer model)))

;; ============================================================================
;; Tests
;; ============================================================================

(module+ test
  (require rackunit)
  
  (test-case "textarea-init creates model"
    (define model (textarea-init #:placeholder "Enter text"))
    (check-equal? (textarea-value model) "")
    (check-equal? (textarea-model-placeholder model) "Enter text")
    (check-false (textarea-focused? model)))
  
  (test-case "textarea-init with initial value"
    (define model (textarea-init #:initial-value "hello\nworld"))
    (check-equal? (textarea-value model) "hello\nworld")
    (check-equal? (textarea-line-count model) 2))
  
  (test-case "focus and blur"
    (define model (textarea-init))
    (define-values (focused _) (textarea-update model (textarea-focus-msg)))
    (check-true (textarea-focused? focused))
    (define-values (blurred _2) (textarea-update focused (textarea-blur-msg)))
    (check-false (textarea-focused? blurred)))
  
  (test-case "character input when focused"
    (define model (textarea-init))
    (define-values (focused _) (textarea-update model (textarea-focus-msg)))
    (define-values (typed cmds)
      (textarea-update focused (key-event #f #\a (set) #"")))
    (check-equal? (textarea-value typed) "a")
    (check-equal? (length cmds) 1)
    (check-pred textarea-changed-msg? (car cmds)))
  
  (test-case "enter creates new line"
    (define model (textarea-init #:initial-value "hello"))
    (define-values (focused _) (textarea-update model (textarea-focus-msg)))
    (define-values (after cmds) (textarea-update focused (key-event 'enter #f (set) #"")))
    (check-equal? (textarea-value after) "hello\n")
    (check-equal? (textarea-line-count after) 2))
  
  (test-case "max-lines limits newlines"
    (define model (textarea-init #:max-lines 2 #:initial-value "line1\nline2"))
    (define-values (focused _) (textarea-update model (textarea-focus-msg)))
    (define-values (after _2) (textarea-update focused (key-event 'enter #f (set) #"")))
    (check-equal? (textarea-line-count after) 2))
  
  (test-case "up arrow moves to previous line"
    (define model (textarea-init #:initial-value "line1\nline2"))
    (define-values (focused _) (textarea-update model (textarea-focus-msg)))
    (define-values (after _2) (textarea-update focused (key-event 'up #f (set) #"")))
    (check-equal? (car (textarea-cursor-position after)) 0))
  
  (test-case "down arrow moves to next line"
    (define model (textarea-init #:initial-value "line1\nline2"))
    (define buf (buffer-move-to (textarea-model-buffer model) 0))
    (define at-start (struct-copy textarea-model model [buffer buf] [focused? #t]))
    (define-values (after _) (textarea-update at-start (key-event 'down #f (set) #"")))
    (check-equal? (car (textarea-cursor-position after)) 1))
  
  (test-case "page-up scrolls"
    (define model (textarea-init #:height 3
                                  #:initial-value "1\n2\n3\n4\n5\n6"))
    (define buf (buffer-move-to (textarea-model-buffer model) 
                                 (string-length "1\n2\n3\n4\n5\n")))
    (define at-bottom (struct-copy textarea-model model [buffer buf] [focused? #t] [scroll-offset 3]))
    (define-values (after _) (textarea-update at-bottom (key-event 'page-up #f (set) #"")))
    (check-true (< (textarea-model-scroll-offset after)
                   (textarea-model-scroll-offset at-bottom))))
  
  (test-case "ctrl+up scrolls without moving cursor"
    (define model (textarea-init #:height 3
                                  #:initial-value "1\n2\n3\n4"))
    (define scrolled (struct-copy textarea-model model [scroll-offset 1] [focused? #t]))
    (define-values (after _) (textarea-update scrolled (key-event 'up #f (set 'ctrl) #"")))
    (check-equal? (textarea-model-scroll-offset after) 0))
  
  (test-case "paste event inserts text"
    (define model (textarea-init))
    (define-values (focused _) (textarea-update model (textarea-focus-msg)))
    (define-values (after cmds) (textarea-update focused (paste-event "hello\nworld")))
    (check-equal? (textarea-value after) "hello\nworld"))
  
  (test-case "set-value message"
    (define model (textarea-init))
    (define-values (after cmds) (textarea-update model (textarea-set-value-msg "new\nvalue")))
    (check-equal? (textarea-value after) "new\nvalue"))
  
  (test-case "view returns doc"
    (define model (textarea-init #:initial-value "hello" #:width 20 #:height 3))
    (define view (textarea-view model))
    (check-true (doc? view)))
  
  (test-case "view with line numbers"
    (define model (textarea-init #:initial-value "a\nb\nc" 
                                  #:width 20 #:height 3 
                                  #:line-numbers? #t))
    (define view (textarea-view model))
    (check-true (doc? view)))
  
  (test-case "cursor position tracking"
    (define model (textarea-init #:initial-value "hello\nworld"))
    (define buf (buffer-move-to (textarea-model-buffer model) 8))
    (define moved (struct-copy textarea-model model [buffer buf]))
    (define pos (textarea-cursor-position moved))
    (check-equal? (car pos) 1)
    (check-equal? (cdr pos) 2))
  
  (test-case "tab inserts spaces"
    (define model (textarea-init))
    (define-values (focused _) (textarea-update model (textarea-focus-msg)))
    (define-values (after _2) (textarea-update focused (key-event 'tab #f (set) #"")))
    (check-equal? (textarea-value after) "    "))
  
  (test-case "escape blurs"
    (define model (textarea-init))
    (define-values (focused _) (textarea-update model (textarea-focus-msg)))
    (define-values (after _2) (textarea-update focused (key-event 'esc #f (set) #"")))
    (check-false (textarea-focused? after)))
  
  (test-case "auto-scroll keeps cursor visible"
    (define model (textarea-init #:height 2 #:initial-value "1\n2\n3\n4"))
    (define buf (textarea-model-buffer model))
    (define at-end (struct-copy textarea-model model [buffer buf] [focused? #t]))
    (define ensured (ensure-cursor-visible at-end))
    (define cursor-line (buffer-current-line buf))
    (define scroll (textarea-model-scroll-offset ensured))
    (check-true (<= scroll cursor-line))
    (check-true (< (- cursor-line scroll) (textarea-model-height ensured)))))
