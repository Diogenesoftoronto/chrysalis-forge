#lang racket/base
(provide (struct-out style)
         (struct-out border)
         empty-style
         style-set
         style-copy
         style-inherit
         style-fg
         style-bg
         style-bold
         style-dim
         style-italic
         style-underline
         style-strikethrough
         style-blink
         style-reverse
         style-padding
         style-margin
         style-border-style
         style-border-fg
         style-border-bg
         style-align
         style-valign
         style-width
         style-height
         style-max-width
         style-max-height
         style-inline?
         style-wrap?
         rounded-border
         square-border
         double-border
         thick-border
         hidden-border
         no-border
         color->ansi-fg
         color->ansi-bg
         style-render
         get-border-struct)

(require racket/string
         racket/list
         racket/match
         "text/measure.rkt")

;; ============================================================================
;; Border Definition
;; ============================================================================

(struct border (top-left top top-right right bottom-right bottom bottom-left left)
  #:transparent)

(define rounded-border
  (border "╭" "─" "╮" "│" "╯" "─" "╰" "│"))

(define square-border
  (border "┌" "─" "┐" "│" "┘" "─" "└" "│"))

(define double-border
  (border "╔" "═" "╗" "║" "╝" "═" "╚" "║"))

(define thick-border
  (border "┏" "━" "┓" "┃" "┛" "━" "┗" "┃"))

(define hidden-border
  (border " " " " " " " " " " " " " " " "))

(define no-border #f)

;; ============================================================================
;; Style Structure
;; ============================================================================

(struct style
  (fg bg
      bold dim italic underline strikethrough blink reverse
      padding margin
      border-style border-fg border-bg
      align valign
      width height max-width max-height
      inline? wrap?)
  #:transparent)

(define empty-style
  (style #f #f
         #f #f #f #f #f #f #f
         '(0 0 0 0) '(0 0 0 0)
         #f #f #f
         'left 'top
         #f #f #f #f
         #f #t))

;; ============================================================================
;; Style Builder Functions
;; ============================================================================

(define (style-set s
                   #:fg [fg (style-fg s)]
                   #:bg [bg (style-bg s)]
                   #:bold [bold (style-bold s)]
                   #:dim [dim (style-dim s)]
                   #:italic [italic (style-italic s)]
                   #:underline [underline (style-underline s)]
                   #:strikethrough [strikethrough (style-strikethrough s)]
                   #:blink [blink (style-blink s)]
                   #:reverse [rev (style-reverse s)]
                   #:padding [padding (style-padding s)]
                   #:margin [margin (style-margin s)]
                   #:border [border-style (style-border-style s)]
                   #:border-fg [border-fg (style-border-fg s)]
                   #:border-bg [border-bg (style-border-bg s)]
                   #:align [align (style-align s)]
                   #:valign [valign (style-valign s)]
                   #:width [width (style-width s)]
                   #:height [height (style-height s)]
                   #:max-width [max-width (style-max-width s)]
                   #:max-height [max-height (style-max-height s)]
                   #:inline? [inline? (style-inline? s)]
                   #:wrap? [wrap? (style-wrap? s)])
  (style fg bg
         bold dim italic underline strikethrough blink rev
         padding margin
         border-style border-fg border-bg
         align valign
         width height max-width max-height
         inline? wrap?))

(define (style-copy s) s)

(define (style-inherit parent child)
  (style (or (style-fg child) (style-fg parent))
         (or (style-bg child) (style-bg parent))
         (or (style-bold child) (style-bold parent))
         (or (style-dim child) (style-dim parent))
         (or (style-italic child) (style-italic parent))
         (or (style-underline child) (style-underline parent))
         (or (style-strikethrough child) (style-strikethrough parent))
         (or (style-blink child) (style-blink parent))
         (or (style-reverse child) (style-reverse parent))
         (if (equal? (style-padding child) '(0 0 0 0))
             (style-padding parent)
             (style-padding child))
         (if (equal? (style-margin child) '(0 0 0 0))
             (style-margin parent)
             (style-margin child))
         (or (style-border-style child) (style-border-style parent))
         (or (style-border-fg child) (style-border-fg parent))
         (or (style-border-bg child) (style-border-bg parent))
         (style-align child)
         (style-valign child)
         (or (style-width child) (style-width parent))
         (or (style-height child) (style-height parent))
         (or (style-max-width child) (style-max-width parent))
         (or (style-max-height child) (style-max-height parent))
         (style-inline? child)
         (style-wrap? child)))

;; Individual setters
(define (style-fg-set s v) (style-set s #:fg v))
(define (style-bg-set s v) (style-set s #:bg v))
(define (style-bold-set s v) (style-set s #:bold v))
(define (style-dim-set s v) (style-set s #:dim v))
(define (style-italic-set s v) (style-set s #:italic v))
(define (style-underline-set s v) (style-set s #:underline v))
(define (style-strikethrough-set s v) (style-set s #:strikethrough v))
(define (style-blink-set s v) (style-set s #:blink v))
(define (style-reverse-set s v) (style-set s #:reverse v))
(define (style-padding-set s v) (style-set s #:padding v))
(define (style-margin-set s v) (style-set s #:margin v))
(define (style-border-set s v) (style-set s #:border v))
(define (style-border-fg-set s v) (style-set s #:border-fg v))
(define (style-border-bg-set s v) (style-set s #:border-bg v))
(define (style-align-set s v) (style-set s #:align v))
(define (style-valign-set s v) (style-set s #:valign v))
(define (style-width-set s v) (style-set s #:width v))
(define (style-height-set s v) (style-set s #:height v))
(define (style-max-width-set s v) (style-set s #:max-width v))
(define (style-max-height-set s v) (style-set s #:max-height v))
(define (style-inline-set s v) (style-set s #:inline? v))
(define (style-wrap-set s v) (style-set s #:wrap? v))

;; ============================================================================
;; Color Support
;; ============================================================================

(define ansi-color-map
  (hash 'black 0 'red 1 'green 2 'yellow 3
        'blue 4 'magenta 5 'cyan 6 'white 7
        'bright-black 8 'bright-red 9 'bright-green 10 'bright-yellow 11
        'bright-blue 12 'bright-magenta 13 'bright-cyan 14 'bright-white 15
        'default #f))

(define (parse-hex-color str)
  (and (string? str)
       (= (string-length str) 7)
       (char=? (string-ref str 0) #\#)
       (let ([r (string->number (substring str 1 3) 16)]
             [g (string->number (substring str 3 5) 16)]
             [b (string->number (substring str 5 7) 16)])
         (and r g b (list r g b)))))

(define (color->ansi-fg color)
  (cond
    [(not color) ""]
    [(symbol? color)
     (define code (hash-ref ansi-color-map color #f))
     (cond
       [(not code) ""]
       [(< code 8) (format "\e[~am" (+ 30 code))]
       [else (format "\e[~am" (+ 82 code))])]
    [(exact-nonnegative-integer? color)
     (format "\e[38;5;~am" color)]
    [(string? color)
     (define rgb (parse-hex-color color))
     (if rgb
         (format "\e[38;2;~a;~a;~am" (first rgb) (second rgb) (third rgb))
         "")]
    [else ""]))

(define (color->ansi-bg color)
  (cond
    [(not color) ""]
    [(symbol? color)
     (define code (hash-ref ansi-color-map color #f))
     (cond
       [(not code) ""]
       [(< code 8) (format "\e[~am" (+ 40 code))]
       [else (format "\e[~am" (+ 92 code))])]
    [(exact-nonnegative-integer? color)
     (format "\e[48;5;~am" color)]
    [(string? color)
     (define rgb (parse-hex-color color))
     (if rgb
         (format "\e[48;2;~a;~a;~am" (first rgb) (second rgb) (third rgb))
         "")]
    [else ""]))

;; ============================================================================
;; Text Attribute Codes
;; ============================================================================

(define (attrs->ansi s)
  (string-append
   (if (style-bold s) "\e[1m" "")
   (if (style-dim s) "\e[2m" "")
   (if (style-italic s) "\e[3m" "")
   (if (style-underline s) "\e[4m" "")
   (if (style-blink s) "\e[5m" "")
   (if (style-reverse s) "\e[7m" "")
   (if (style-strikethrough s) "\e[9m" "")))

(define reset-code "\e[0m")

;; ============================================================================
;; Rendering
;; ============================================================================

(define (get-border-struct s)
  (define b (style-border-style s))
  (cond
    [(border? b) b]
    [(eq? b 'rounded) rounded-border]
    [(eq? b 'square) square-border]
    [(eq? b 'double) double-border]
    [(eq? b 'thick) thick-border]
    [(eq? b 'hidden) hidden-border]
    [(eq? b #t) rounded-border]
    [else #f]))

(define (style-render s str)
  (define lines (split-lines str))
  (define border-struct (get-border-struct s))
  (define has-border? (and border-struct #t))

  (match-define (list p-top p-right p-bottom p-left) (style-padding s))
  (match-define (list m-top m-right m-bottom m-left) (style-margin s))

  (define content-width
    (cond
      [(style-width s)
       (- (style-width s)
          (if has-border? 2 0)
          p-left p-right)]
      [(style-max-width s)
       (min (max-line-width str)
            (- (style-max-width s)
               (if has-border? 2 0)
               p-left p-right))]
      [else (max-line-width str)]))

  (define processed-lines
    (if (style-wrap? s)
        (apply append (map (λ (l) (wrap-text l content-width)) lines))
        lines))

  (define content-height
    (cond
      [(style-height s)
       (- (style-height s)
          (if has-border? 2 0)
          p-top p-bottom)]
      [(style-max-height s)
       (min (length processed-lines)
            (- (style-max-height s)
               (if has-border? 2 0)
               p-top p-bottom))]
      [else (length processed-lines)]))

  (define aligned-lines
    (for/list ([line (in-list processed-lines)]
               [i (in-naturals)]
               #:when (< i content-height))
      (define line-width (text-width line))
      (define padded-width (+ content-width p-left p-right))
      (case (style-align s)
        [(left) (pad-right (string-append (make-string p-left #\space) line)
                           padded-width)]
        [(right) (pad-left (string-append line (make-string p-right #\space))
                           padded-width)]
        [(center) (pad-center line padded-width)]
        [else (pad-right (string-append (make-string p-left #\space) line)
                         padded-width)])))

  (define empty-line (make-string (+ content-width p-left p-right) #\space))

  (define lines-with-vpad
    (append
     (make-list p-top empty-line)
     aligned-lines
     (make-list (max 0 (- content-height (length aligned-lines))) empty-line)
     (make-list p-bottom empty-line)))

  (define valigned-lines
    (case (style-valign s)
      [(top) lines-with-vpad]
      [(bottom)
       (define target-height (+ content-height p-top p-bottom))
       (define current-len (length lines-with-vpad))
       (if (< current-len target-height)
           (append (make-list (- target-height current-len) empty-line)
                   lines-with-vpad)
           lines-with-vpad)]
      [(middle)
       (define target-height (+ content-height p-top p-bottom))
       (define current-len (length lines-with-vpad))
       (if (< current-len target-height)
           (let* ([diff (- target-height current-len)]
                  [top-padding (quotient diff 2)]
                  [bottom-padding (- diff top-padding)])
             (append (make-list top-padding empty-line)
                     lines-with-vpad
                     (make-list bottom-padding empty-line)))
           lines-with-vpad)]
      [else lines-with-vpad]))

  (define fg-code (color->ansi-fg (style-fg s)))
  (define bg-code (color->ansi-bg (style-bg s)))
  (define attr-code (attrs->ansi s))
  (define style-prefix (string-append fg-code bg-code attr-code))
  (define style-suffix (if (or (style-fg s) (style-bg s)
                               (style-bold s) (style-dim s) (style-italic s)
                               (style-underline s) (style-strikethrough s)
                               (style-blink s) (style-reverse s))
                           reset-code
                           ""))

  (define bordered-lines
    (if has-border?
        (let* ([b border-struct]
               [border-fg-code (color->ansi-fg (style-border-fg s))]
               [border-bg-code (color->ansi-bg (style-border-bg s))]
               [border-prefix (string-append border-fg-code border-bg-code)]
               [border-suffix (if (or (style-border-fg s) (style-border-bg s))
                                  reset-code
                                  "")]
               [inner-width (+ content-width p-left p-right)]
               [top-line (string-append
                          border-prefix
                          (border-top-left b)
                          (make-string inner-width
                                       (string-ref (border-top b) 0))
                          (border-top-right b)
                          border-suffix)]
               [bottom-line (string-append
                             border-prefix
                             (border-bottom-left b)
                             (make-string inner-width
                                          (string-ref (border-bottom b) 0))
                             (border-bottom-right b)
                             border-suffix)]
               [content-lines
                (for/list ([line (in-list valigned-lines)])
                  (string-append border-prefix (border-left b) border-suffix
                                 style-prefix line style-suffix
                                 border-prefix (border-right b) border-suffix))])
          (append (list top-line) content-lines (list bottom-line)))
        (for/list ([line (in-list valigned-lines)])
          (string-append style-prefix line style-suffix))))

  (define margin-left-str (make-string m-left #\space))
  (define margin-right-str (make-string m-right #\space))

  (define margined-lines
    (let* ([total-width (+ (if has-border? 2 0)
                           content-width p-left p-right)]
           [empty-margin-line (string-append margin-left-str
                                             (make-string total-width #\space)
                                             margin-right-str)]
           [top-margin (make-list m-top empty-margin-line)]
           [bottom-margin (make-list m-bottom empty-margin-line)]
           [content-with-side-margin
            (for/list ([line (in-list bordered-lines)])
              (string-append margin-left-str line margin-right-str))])
      (append top-margin content-with-side-margin bottom-margin)))

  (string-join margined-lines "\n"))

;; ============================================================================
;; Tests
;; ============================================================================

(module+ test
  (require rackunit)

  (test-case "empty-style has correct defaults"
             (check-false (style-fg empty-style))
             (check-false (style-bg empty-style))
             (check-false (style-bold empty-style))
             (check-equal? (style-padding empty-style) '(0 0 0 0))
             (check-equal? (style-margin empty-style) '(0 0 0 0))
             (check-eq? (style-align empty-style) 'left)
             (check-true (style-wrap? empty-style)))

  (test-case "style-set creates new style with changes"
             (define s (style-set empty-style #:fg 'red #:bold #t))
             (check-eq? (style-fg s) 'red)
             (check-true (style-bold s))
             (check-false (style-bg s)))

  (test-case "style-inherit merges parent and child"
             (define parent (style-set empty-style #:fg 'blue #:bold #t))
             (define child (style-set empty-style #:bg 'white))
             (define merged (style-inherit parent child))
             (check-eq? (style-fg merged) 'blue)
             (check-eq? (style-bg merged) 'white)
             (check-true (style-bold merged)))

  (test-case "color->ansi-fg handles different color formats"
             (check-equal? (color->ansi-fg 'red) "\e[31m")
             (check-equal? (color->ansi-fg 'bright-red) "\e[91m")
             (check-equal? (color->ansi-fg 196) "\e[38;5;196m")
             (check-equal? (color->ansi-fg "#ff0000") "\e[38;2;255;0;0m")
             (check-equal? (color->ansi-fg #f) ""))

  (test-case "color->ansi-bg handles different color formats"
             (check-equal? (color->ansi-bg 'blue) "\e[44m")
             (check-equal? (color->ansi-bg 21) "\e[48;5;21m")
             (check-equal? (color->ansi-bg "#0000ff") "\e[48;2;0;0;255m"))

  (test-case "border structs have correct characters"
             (check-equal? (border-top-left rounded-border) "╭")
             (check-equal? (border-top-right square-border) "┐")
             (check-equal? (border-left double-border) "║"))

  (test-case "style-render applies foreground color"
             (define s (style-set empty-style #:fg 'red))
             (define result (style-render s "hello"))
             (check-true (string-contains? result "\e[31m"))
             (check-true (string-contains? result "hello"))
             (check-true (string-contains? result "\e[0m")))

  (test-case "style-render applies text attributes"
             (define s (style-set empty-style #:bold #t #:italic #t))
             (define result (style-render s "text"))
             (check-true (string-contains? result "\e[1m"))
             (check-true (string-contains? result "\e[3m")))

  (test-case "style-render applies padding"
             (define s (style-set empty-style #:padding '(1 2 1 2)))
             (define result (style-render s "hi"))
             (define lines (split-lines result))
             (check-equal? (length lines) 3)
             (check-true (>= (text-width (second lines)) 6)))

  (test-case "style-render applies margin"
             (define s (style-set empty-style #:margin '(1 0 1 0)))
             (define result (style-render s "hi"))
             (define lines (split-lines result))
             (check-equal? (length lines) 3))

  (test-case "style-render applies border"
             (define s (style-set empty-style #:border 'rounded))
             (define result (style-render s "hi"))
             (check-true (string-contains? result "╭"))
             (check-true (string-contains? result "╯")))

  (test-case "style-render handles multi-line content"
             (define s (style-set empty-style #:fg 'green #:border 'square))
             (define result (style-render s "line1\nline2"))
             (define lines (split-lines result))
             (check-equal? (length lines) 4))

  (test-case "style-render respects width constraint"
             (define s (style-set empty-style #:width 10 #:border 'rounded))
             (define result (style-render s "hi"))
             (define lines (split-lines result))
             (for ([line (in-list lines)])
               (check-equal? (text-width line) 10)))

  (test-case "style-render handles alignment"
             (define s-left (style-set empty-style #:width 10 #:align 'left))
             (define s-right (style-set empty-style #:width 10 #:align 'right))
             (define s-center (style-set empty-style #:width 10 #:align 'center))
             (check-true (string-prefix? (strip-ansi (style-render s-left "hi")) "hi"))
             (check-true (string-suffix? (strip-ansi (style-render s-right "hi")) "hi"))
             (define center-result (strip-ansi (style-render s-center "hi")))
             (check-true (string-contains? center-result "    hi    ")))

  (test-case "style-render wraps text when wrap? is true"
             (define s (style-set empty-style #:width 6 #:wrap? #t))
             (define result (style-render s "hello world"))
             (define lines (split-lines result))
             (check-true (> (length lines) 1))))
