#lang racket/base

(require racket/match
         racket/string
         racket/set
         "../event.rkt"
         "../text/buffer.rkt")

(provide (struct-out text-input-model)
         (struct-out text-input-styles)
         (struct-out validation)

         ;; Messages
         (struct-out text-input-focus-msg)
         (struct-out text-input-blur-msg)
         (struct-out text-input-set-value-msg)
         (struct-out text-input-submit-msg)
         (struct-out text-input-changed-msg)

         ;; Init/Update/View
         text-input-init
         text-input-update
         text-input-view

         ;; Queries
         text-input-value
         text-input-valid?
         text-input-focused?

         ;; Validation helpers
         validate-not-empty
         validate-email
         validate-length
         validate-pattern)

;; ============================================================================
;; Styles (minimal inline definition until style.rkt exists)
;; ============================================================================

(struct text-input-styles (normal focused error placeholder cursor)
  #:transparent)

(define default-styles
  (text-input-styles
   ""      ; normal - no styling
   ""      ; focused - no styling
   ""      ; error - no styling
   ""      ; placeholder - no styling
   "│"))   ; cursor character

;; ============================================================================
;; Validation
;; ============================================================================

(struct validation (ok? message) #:transparent)

(define validation-ok (validation #t ""))

(define (validate-not-empty text)
  (if (string=? (string-trim text) "")
      (validation #f "Cannot be empty")
      validation-ok))

(define (validate-email text)
  (if (regexp-match? #rx"^[^@]+@[^@]+\\.[^@]+$" text)
      validation-ok
      (validation #f "Invalid email address")))

(define (validate-length min-len max-len)
  (λ (text)
    (define len (string-length text))
    (cond
      [(< len min-len) (validation #f (format "Must be at least ~a characters" min-len))]
      [(> len max-len) (validation #f (format "Must be at most ~a characters" max-len))]
      [else validation-ok])))

(define (validate-pattern pattern msg)
  (λ (text)
    (if (regexp-match? pattern text)
        validation-ok
        (validation #f msg))))

;; ============================================================================
;; Model
;; ============================================================================

(struct text-input-model
  (buffer placeholder prompt focused? char-limit validation-fn mask-char styles)
  #:transparent)

(define (text-input-init #:placeholder [placeholder ""]
                         #:prompt [prompt ""]
                         #:validation [validation-fn #f]
                         #:char-limit [char-limit #f]
                         #:mask-char [mask-char #f]
                         #:styles [styles default-styles]
                         #:initial-value [initial-value ""])
  (text-input-model
   (make-buffer initial-value)
   placeholder
   prompt
   #f
   char-limit
   validation-fn
   mask-char
   styles))

;; ============================================================================
;; Messages
;; ============================================================================

(struct text-input-focus-msg () #:transparent)
(struct text-input-blur-msg () #:transparent)
(struct text-input-set-value-msg (value) #:transparent)
(struct text-input-submit-msg (value) #:transparent)
(struct text-input-changed-msg (value) #:transparent)

;; ============================================================================
;; Update
;; ============================================================================

(define (text-input-update model evt)
  (match evt
    ;; Focus messages
    [(text-input-focus-msg)
     (values (struct-copy text-input-model model [focused? #t]) '())]

    [(text-input-blur-msg)
     (values (struct-copy text-input-model model [focused? #f]) '())]

    ;; Set value message
    [(text-input-set-value-msg value)
     (define new-buf (make-buffer value))
     (values (struct-copy text-input-model model [buffer new-buf])
             (list (text-input-changed-msg value)))]

    ;; Key events
    [(key-event key rune mods _)
     (cond
       ;; Not focused - ignore
       [(not (text-input-model-focused? model))
        (values model '())]

       ;; Enter - submit
       [(eq? key 'enter)
        (values model (list (text-input-submit-msg (text-input-value model))))]

       ;; Escape - blur
       [(eq? key 'esc)
        (values (struct-copy text-input-model model [focused? #f]) '())]

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

       ;; Up arrow (for multiline - but single-line just moves to start)
       [(eq? key 'up)
        (handle-cursor model buffer-move-home)]

       ;; Down arrow (for multiline - but single-line just moves to end)
       [(eq? key 'down)
        (handle-cursor model buffer-move-end)]

       ;; Ctrl+K - kill to end of line
       [(and (set-member? mods 'ctrl) (equal? rune #\k))
        (handle-edit model buffer-delete-to-end)]

       ;; Ctrl+U - kill to start of line
       [(and (set-member? mods 'ctrl) (equal? rune #\u))
        (handle-edit model buffer-delete-to-start)]

       ;; Ctrl+W - delete word backward
       [(and (set-member? mods 'ctrl) (equal? rune #\w))
        (handle-edit model buffer-delete-word)]

       ;; Ctrl+A - move to start
       [(and (set-member? mods 'ctrl) (equal? rune #\a))
        (handle-cursor model buffer-move-home)]

       ;; Ctrl+E - move to end
       [(and (set-member? mods 'ctrl) (equal? rune #\e))
        (handle-cursor model buffer-move-end)]

       ;; Ctrl+F - forward char
       [(and (set-member? mods 'ctrl) (equal? rune #\f))
        (handle-cursor model buffer-move-right)]

       ;; Ctrl+B - backward char
       [(and (set-member? mods 'ctrl) (equal? rune #\b))
        (handle-cursor model buffer-move-left)]

       ;; Character input
       [(and rune (char-graphic? rune))
        (handle-char-input model rune)]

       ;; Space (key='space with rune=#\space)
       [(eq? key 'space)
        (handle-char-input model #\space)]

       [else (values model '())])]

    ;; Paste event
    [(paste-event text)
     (if (text-input-model-focused? model)
         (handle-paste model text)
         (values model '()))]

    ;; Other events - pass through
    [_ (values model '())]))

(define (handle-cursor model op)
  (define buf (text-input-model-buffer model))
  (values (struct-copy text-input-model model [buffer (op buf)]) '()))

(define (handle-edit model op)
  (define buf (text-input-model-buffer model))
  (define new-buf (op buf))
  (define new-model (struct-copy text-input-model model [buffer new-buf]))
  (values new-model (list (text-input-changed-msg (buffer-text new-buf)))))

(define (handle-char-input model char)
  (define buf (text-input-model-buffer model))
  (define limit (text-input-model-char-limit model))
  (cond
    [(and limit (>= (buffer-length buf) limit))
     (values model '())]
    [else
     (define new-buf (buffer-insert buf (string char)))
     (define new-model (struct-copy text-input-model model [buffer new-buf]))
     (values new-model (list (text-input-changed-msg (buffer-text new-buf))))]))

(define (handle-paste model text)
  (define buf (text-input-model-buffer model))
  (define limit (text-input-model-char-limit model))
  (define clean-text (string-replace text "\n" " "))
  (define to-insert
    (if limit
        (let* ([current-len (buffer-length buf)]
               [available (max 0 (- limit current-len))])
          (if (> (string-length clean-text) available)
              (substring clean-text 0 available)
              clean-text))
        clean-text))
  (if (string=? to-insert "")
      (values model '())
      (let* ([new-buf (buffer-insert buf to-insert)]
             [new-model (struct-copy text-input-model model [buffer new-buf])])
        (values new-model (list (text-input-changed-msg (buffer-text new-buf)))))))

;; ============================================================================
;; View
;; ============================================================================

(define (text-input-view model width)
  (match-define (text-input-model buf placeholder prompt focused? _ validation-fn mask-char styles) model)
  (define text (buffer-text buf))
  (define cursor-pos (buffer-cursor buf))
  (define cursor-char (text-input-styles-cursor styles))

  (define prompt-len (string-length prompt))
  (define content-width (max 1 (- width prompt-len)))

  (define display-text
    (cond
      [(and (string=? text "") (not focused?))
       placeholder]
      [mask-char
       (make-string (string-length text) mask-char)]
      [else text]))

  (define is-placeholder? (and (string=? text "") (not focused?)))

  (define (insert-cursor str pos)
    (if (not focused?)
        str
        (let ([pos (min pos (string-length str))])
          (string-append
           (substring str 0 pos)
           cursor-char
           (if (< pos (string-length str))
               (substring str pos)
               "")))))

  (define cursor-display-pos
    (if mask-char cursor-pos cursor-pos))

  (define with-cursor
    (if is-placeholder?
        display-text
        (insert-cursor display-text cursor-display-pos)))

  (define truncated
    (if (> (string-length with-cursor) content-width)
        (let* ([start (max 0 (- cursor-pos (quotient content-width 2)))]
               [end (min (string-length with-cursor) (+ start content-width))]
               [start (max 0 (- end content-width))])
          (substring with-cursor start end))
        with-cursor))

  (define padded
    (if (< (string-length truncated) content-width)
        (string-append truncated (make-string (- content-width (string-length truncated)) #\space))
        truncated))

  (define valid? (text-input-valid? model))

  (string-append prompt padded))

;; ============================================================================
;; Queries
;; ============================================================================

(define (text-input-value model)
  (buffer-text (text-input-model-buffer model)))

(define (text-input-valid? model)
  (define validation-fn (text-input-model-validation-fn model))
  (if validation-fn
      (validation-ok? (validation-fn (text-input-value model)))
      #t))

(define (text-input-focused? model)
  (text-input-model-focused? model))

;; ============================================================================
;; Tests
;; ============================================================================

(module+ test
  (require rackunit)

  (test-case "text-input-init creates model"
             (define model (text-input-init #:placeholder "Enter name"))
             (check-equal? (text-input-value model) "")
             (check-equal? (text-input-model-placeholder model) "Enter name")
             (check-false (text-input-focused? model)))

  (test-case "text-input-init with initial value"
             (define model (text-input-init #:initial-value "hello"))
             (check-equal? (text-input-value model) "hello"))

  (test-case "focus and blur"
             (define model (text-input-init))
             (define-values (focused _) (text-input-update model (text-input-focus-msg)))
             (check-true (text-input-focused? focused))
             (define-values (blurred _2) (text-input-update focused (text-input-blur-msg)))
             (check-false (text-input-focused? blurred)))

  (test-case "character input when focused"
             (define model (text-input-init))
             (define-values (focused _) (text-input-update model (text-input-focus-msg)))
             (define-values (typed cmds)
               (text-input-update focused (key-event #f #\a (set) #"")))
             (check-equal? (text-input-value typed) "a")
             (check-equal? (length cmds) 1)
             (check-pred text-input-changed-msg? (car cmds)))

  (test-case "character input when not focused is ignored"
             (define model (text-input-init))
             (define-values (after _) (text-input-update model (key-event #f #\a (set) #"")))
             (check-equal? (text-input-value after) ""))

  (test-case "backspace deletes character"
             (define model (text-input-init #:initial-value "hello"))
             (define-values (focused _) (text-input-update model (text-input-focus-msg)))
             (define-values (after cmds) (text-input-update focused (key-event 'backspace #f (set) #"")))
             (check-equal? (text-input-value after) "hell"))

  (test-case "delete removes forward"
             (define model (text-input-init #:initial-value "hello"))
             (define-values (focused _) (text-input-update model (text-input-focus-msg)))
             (define buf (buffer-move-to (text-input-model-buffer focused) 0))
             (define at-start (struct-copy text-input-model focused [buffer buf]))
             (define-values (after _2) (text-input-update at-start (key-event 'delete #f (set) #"")))
             (check-equal? (text-input-value after) "ello"))

  (test-case "home moves to start"
             (define model (text-input-init #:initial-value "hello"))
             (define-values (focused _) (text-input-update model (text-input-focus-msg)))
             (define-values (after _2) (text-input-update focused (key-event 'home #f (set) #"")))
             (check-equal? (buffer-cursor (text-input-model-buffer after)) 0))

  (test-case "end moves to end"
             (define model (text-input-init #:initial-value "hello"))
             (define buf (buffer-move-to (text-input-model-buffer model) 0))
             (define at-start (struct-copy text-input-model model [buffer buf] [focused? #t]))
             (define-values (after _) (text-input-update at-start (key-event 'end #f (set) #"")))
             (check-equal? (buffer-cursor (text-input-model-buffer after)) 5))

  (test-case "left arrow moves cursor left"
             (define model (text-input-init #:initial-value "hello"))
             (define-values (focused _) (text-input-update model (text-input-focus-msg)))
             (define-values (after _2) (text-input-update focused (key-event 'left #f (set) #"")))
             (check-equal? (buffer-cursor (text-input-model-buffer after)) 4))

  (test-case "right arrow moves cursor right"
             (define model (text-input-init #:initial-value "hello"))
             (define buf (buffer-move-to (text-input-model-buffer model) 2))
             (define at-middle (struct-copy text-input-model model [buffer buf] [focused? #t]))
             (define-values (after _) (text-input-update at-middle (key-event 'right #f (set) #"")))
             (check-equal? (buffer-cursor (text-input-model-buffer after)) 3))

  (test-case "ctrl+left moves word left"
             (define model (text-input-init #:initial-value "hello world"))
             (define-values (focused _) (text-input-update model (text-input-focus-msg)))
             (define-values (after _2) (text-input-update focused (key-event 'left #f (set 'ctrl) #"")))
             (check-equal? (buffer-cursor (text-input-model-buffer after)) 6))

  (test-case "ctrl+k kills to end"
             (define model (text-input-init #:initial-value "hello world"))
             (define buf (buffer-move-to (text-input-model-buffer model) 5))
             (define at-middle (struct-copy text-input-model model [buffer buf] [focused? #t]))
             (define-values (after _) (text-input-update at-middle (key-event #f #\k (set 'ctrl) #"")))
             (check-equal? (text-input-value after) "hello"))

  (test-case "ctrl+u kills to start"
             (define model (text-input-init #:initial-value "hello world"))
             (define buf (buffer-move-to (text-input-model-buffer model) 6))
             (define at-middle (struct-copy text-input-model model [buffer buf] [focused? #t]))
             (define-values (after _) (text-input-update at-middle (key-event #f #\u (set 'ctrl) #"")))
             (check-equal? (text-input-value after) "world"))

  (test-case "ctrl+w deletes word backward"
             (define model (text-input-init #:initial-value "hello world"))
             (define-values (focused _) (text-input-update model (text-input-focus-msg)))
             (define-values (after _2) (text-input-update focused (key-event #f #\w (set 'ctrl) #"")))
             (check-equal? (text-input-value after) "hello "))

  (test-case "enter submits"
             (define model (text-input-init #:initial-value "hello"))
             (define-values (focused _) (text-input-update model (text-input-focus-msg)))
             (define-values (after cmds) (text-input-update focused (key-event 'enter #f (set) #"")))
             (check-equal? (length cmds) 1)
             (check-pred text-input-submit-msg? (car cmds))
             (check-equal? (text-input-submit-msg-value (car cmds)) "hello"))

  (test-case "escape blurs"
             (define model (text-input-init))
             (define-values (focused _) (text-input-update model (text-input-focus-msg)))
             (define-values (after _2) (text-input-update focused (key-event 'esc #f (set) #"")))
             (check-false (text-input-focused? after)))

  (test-case "char-limit enforced"
             (define model (text-input-init #:char-limit 5 #:initial-value "hell"))
             (define-values (focused _) (text-input-update model (text-input-focus-msg)))
             (define-values (typed1 _2) (text-input-update focused (key-event #f #\o (set) #"")))
             (check-equal? (text-input-value typed1) "hello")
             (define-values (typed2 _3) (text-input-update typed1 (key-event #f #\! (set) #"")))
             (check-equal? (text-input-value typed2) "hello"))

  (test-case "paste event inserts text"
             (define model (text-input-init))
             (define-values (focused _) (text-input-update model (text-input-focus-msg)))
             (define-values (after cmds) (text-input-update focused (paste-event "hello")))
             (check-equal? (text-input-value after) "hello"))

  (test-case "paste respects char-limit"
             (define model (text-input-init #:char-limit 3))
             (define-values (focused _) (text-input-update model (text-input-focus-msg)))
             (define-values (after _2) (text-input-update focused (paste-event "hello")))
             (check-equal? (text-input-value after) "hel"))

  (test-case "set-value message"
             (define model (text-input-init))
             (define-values (after cmds) (text-input-update model (text-input-set-value-msg "new value")))
             (check-equal? (text-input-value after) "new value"))

  (test-case "validation - not empty"
             (define model (text-input-init #:validation validate-not-empty))
             (check-false (text-input-valid? model))
             (define-values (after _) (text-input-update model (text-input-set-value-msg "hello")))
             (check-true (text-input-valid? after)))

  (test-case "validation - email"
             (define model (text-input-init #:validation validate-email))
             (define-values (bad _) (text-input-update model (text-input-set-value-msg "notanemail")))
             (check-false (text-input-valid? bad))
             (define-values (good _2) (text-input-update model (text-input-set-value-msg "user@example.com")))
             (check-true (text-input-valid? good)))

  (test-case "validation - length"
             (define model (text-input-init #:validation (validate-length 3 10)))
             (define-values (short _) (text-input-update model (text-input-set-value-msg "ab")))
             (check-false (text-input-valid? short))
             (define-values (good _2) (text-input-update model (text-input-set-value-msg "hello")))
             (check-true (text-input-valid? good))
             (define-values (long _3) (text-input-update model (text-input-set-value-msg "hello world!")))
             (check-false (text-input-valid? long)))

  (test-case "view shows prompt"
             (define model (text-input-init #:prompt "> " #:initial-value "test"))
             (define view (text-input-view model 20))
             (check-true (string-prefix? view "> ")))

  (test-case "view shows placeholder when empty and unfocused"
             (define model (text-input-init #:placeholder "Enter text"))
             (define view (text-input-view model 20))
             (check-true (string-contains? view "Enter text")))

  (test-case "view shows cursor when focused"
             (define model (text-input-init #:initial-value "hi"))
             (define-values (focused _) (text-input-update model (text-input-focus-msg)))
             (define view (text-input-view focused 10))
             (check-true (string-contains? view "│")))

  (test-case "view masks password"
             (define model (text-input-init #:initial-value "secret" #:mask-char #\*))
             (define view (text-input-view model 20))
             (check-true (string-contains? view "******"))
             (check-false (string-contains? view "secret")))

  (test-case "ctrl+a moves to start (emacs)"
             (define model (text-input-init #:initial-value "hello"))
             (define-values (focused _) (text-input-update model (text-input-focus-msg)))
             (define-values (after _2) (text-input-update focused (key-event #f #\a (set 'ctrl) #"")))
             (check-equal? (buffer-cursor (text-input-model-buffer after)) 0))

  (test-case "ctrl+e moves to end (emacs)"
             (define model (text-input-init #:initial-value "hello"))
             (define buf (buffer-move-to (text-input-model-buffer model) 0))
             (define at-start (struct-copy text-input-model model [buffer buf] [focused? #t]))
             (define-values (after _) (text-input-update at-start (key-event #f #\e (set 'ctrl) #"")))
             (check-equal? (buffer-cursor (text-input-model-buffer after)) 5)))
