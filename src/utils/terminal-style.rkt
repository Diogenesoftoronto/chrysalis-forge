#lang racket/base
;; Terminal Styling Library
;; Provides ANSI color codes, text formatting, themes, and pre-styled messages.

(provide
 ;; Parameters
 color-enabled-param
 current-theme
 
 ;; Core styling
 color
 bright-color
 styled
 
 ;; Text formatting
 bold
 dim
 italic
 underline
 blink
 strikethrough
 reset-style
 
 ;; Text effects
 rainbow
 gradient
 
 ;; Pre-styled messages
 error-message
 success-message
 warning-message
 info-message
 
 ;; Themes
 set-theme!
 available-themes
 theme-color)

(require racket/string
         racket/list
         racket/math
         "debug.rkt")

;; ---------------------------------------------------------------------------
;; Color Support Detection
;; ---------------------------------------------------------------------------

(define (detect-color-support)
  (cond
    [(getenv "NO_COLOR") #f]
    [(getenv "FORCE_COLOR") #t]
    [else
     (define term (getenv "TERM"))
     (and term
          (not (string=? term "dumb"))
          (or (string-contains? term "color")
              (string-contains? term "xterm")
              (string-contains? term "screen")
              (string-contains? term "tmux")
              (string-contains? term "vt100")
              (string-contains? term "linux")
              (string-contains? term "ansi")
              (string-contains? term "rxvt")
              (string-contains? term "konsole")
              (string-contains? term "kitty")
              (string-contains? term "alacritty")))]))

(define color-enabled-param (make-parameter (detect-color-support)))

;; ---------------------------------------------------------------------------
;; ANSI Escape Codes
;; ---------------------------------------------------------------------------

(define ESC "\033[")
(define RESET "\033[0m")

;; Standard foreground colors
(define FG-COLORS
  (hasheq 'black   "30"
          'red     "31"
          'green   "32"
          'yellow  "33"
          'blue    "34"
          'magenta "35"
          'cyan    "36"
          'white   "37"
          'default "39"))

;; Bright foreground colors
(define FG-BRIGHT-COLORS
  (hasheq 'black   "90"
          'red     "91"
          'green   "92"
          'yellow  "93"
          'blue    "94"
          'magenta "95"
          'cyan    "96"
          'white   "97"))

;; Background colors
(define BG-COLORS
  (hasheq 'black   "40"
          'red     "41"
          'green   "42"
          'yellow  "43"
          'blue    "44"
          'magenta "45"
          'cyan    "46"
          'white   "47"
          'default "49"))

;; Bright background colors
(define BG-BRIGHT-COLORS
  (hasheq 'black   "100"
          'red     "101"
          'green   "102"
          'yellow  "103"
          'blue    "104"
          'magenta "105"
          'cyan    "106"
          'white   "107"))

;; Text attributes
(define ATTRS
  (hasheq 'bold          "1"
          'dim           "2"
          'italic        "3"
          'underline     "4"
          'blink         "5"
          'rapid-blink   "6"
          'reverse       "7"
          'hidden        "8"
          'strikethrough "9"))

;; ---------------------------------------------------------------------------
;; Core Styling Functions
;; ---------------------------------------------------------------------------

(define (wrap-ansi codes text)
  (if (color-enabled-param)
      (string-append ESC (string-join codes ";") "m" text RESET)
      text))

(define (color col text)
  (define code (hash-ref FG-COLORS col #f))
  (if code
      (wrap-ansi (list code) text)
      (begin
        (log-debug 1 'style "Unknown color: ~a" col)
        text)))

(define (bright-color col text)
  (define code (hash-ref FG-BRIGHT-COLORS col #f))
  (if code
      (wrap-ansi (list code) text)
      (begin
        (log-debug 1 'style "Unknown bright color: ~a" col)
        text)))

(define (styled text
                #:fg [fg #f]
                #:bg [bg #f]
                #:bright-fg? [bright-fg? #f]
                #:bright-bg? [bright-bg? #f]
                #:bold? [bold? #f]
                #:dim? [dim? #f]
                #:italic? [italic? #f]
                #:underline? [underline? #f]
                #:blink? [blink? #f]
                #:strikethrough? [strikethrough? #f])
  (define codes '())
  
  ;; Add foreground color
  (when fg
    (define fg-code
      (if bright-fg?
          (hash-ref FG-BRIGHT-COLORS fg #f)
          (hash-ref FG-COLORS fg #f)))
    (when fg-code
      (set! codes (cons fg-code codes))))
  
  ;; Add background color
  (when bg
    (define bg-code
      (if bright-bg?
          (hash-ref BG-BRIGHT-COLORS bg #f)
          (hash-ref BG-COLORS bg #f)))
    (when bg-code
      (set! codes (cons bg-code codes))))
  
  ;; Add text attributes
  (when bold? (set! codes (cons (hash-ref ATTRS 'bold) codes)))
  (when dim? (set! codes (cons (hash-ref ATTRS 'dim) codes)))
  (when italic? (set! codes (cons (hash-ref ATTRS 'italic) codes)))
  (when underline? (set! codes (cons (hash-ref ATTRS 'underline) codes)))
  (when blink? (set! codes (cons (hash-ref ATTRS 'blink) codes)))
  (when strikethrough? (set! codes (cons (hash-ref ATTRS 'strikethrough) codes)))
  
  (if (null? codes)
      text
      (wrap-ansi (reverse codes) text)))

;; ---------------------------------------------------------------------------
;; Text Formatting Shortcuts
;; ---------------------------------------------------------------------------

(define (bold text)
  (wrap-ansi (list (hash-ref ATTRS 'bold)) text))

(define (dim text)
  (wrap-ansi (list (hash-ref ATTRS 'dim)) text))

(define (italic text)
  (wrap-ansi (list (hash-ref ATTRS 'italic)) text))

(define (underline text)
  (wrap-ansi (list (hash-ref ATTRS 'underline)) text))

(define (blink text)
  (wrap-ansi (list (hash-ref ATTRS 'blink)) text))

(define (strikethrough text)
  (wrap-ansi (list (hash-ref ATTRS 'strikethrough)) text))

(define (reset-style)
  (if (color-enabled-param) RESET ""))

;; ---------------------------------------------------------------------------
;; Text Effects
;; ---------------------------------------------------------------------------

(define RAINBOW-COLORS '(red yellow green cyan blue magenta))

(define (rainbow text)
  (if (not (color-enabled-param))
      text
      (let ([chars (string->list text)]
            [num-colors (length RAINBOW-COLORS)])
        (apply string-append
               (for/list ([c (in-list chars)]
                          [i (in-naturals)])
                 (define col (list-ref RAINBOW-COLORS (modulo i num-colors)))
                 (color col (string c)))))))

;; RGB values for gradient interpolation
(define COLOR-RGB
  (hasheq 'black   '(0 0 0)
          'red     '(255 0 0)
          'green   '(0 255 0)
          'yellow  '(255 255 0)
          'blue    '(0 0 255)
          'magenta '(255 0 255)
          'cyan    '(0 255 255)
          'white   '(255 255 255)))

(define (rgb-code r g b)
  (format "38;2;~a;~a;~a" r g b))

(define (interpolate-color start-rgb end-rgb t)
  (define (lerp a b) (exact-round (+ a (* t (- b a)))))
  (list (lerp (first start-rgb) (first end-rgb))
        (lerp (second start-rgb) (second end-rgb))
        (lerp (third start-rgb) (third end-rgb))))

(define (gradient text start-color end-color)
  (if (not (color-enabled-param))
      text
      (let* ([chars (string->list text)]
             [len (length chars)]
             [start-rgb (hash-ref COLOR-RGB start-color '(255 255 255))]
             [end-rgb (hash-ref COLOR-RGB end-color '(255 255 255))])
        (if (<= len 1)
            (color start-color text)
            (apply string-append
                   (for/list ([c (in-list chars)]
                              [i (in-naturals)])
                     (define t (/ i (sub1 len)))
                     (define rgb (interpolate-color start-rgb end-rgb t))
                     (define code (apply rgb-code rgb))
                     (string-append ESC code "m" (string c) RESET)))))))

;; ---------------------------------------------------------------------------
;; Theme System
;; ---------------------------------------------------------------------------

(define THEMES
  (hasheq
   'default
   (hasheq 'primary   'cyan
           'secondary 'white
           'success   'green
           'warning   'yellow
           'error     'red
           'info      'blue
           'muted     'white
           'accent    'magenta)
   
   'cyberpunk
   (hasheq 'primary   'magenta
           'secondary 'cyan
           'success   'green
           'warning   'yellow
           'error     'red
           'info      'cyan
           'muted     'white
           'accent    'magenta)
   
   'minimal
   (hasheq 'primary   'white
           'secondary 'white
           'success   'white
           'warning   'white
           'error     'white
           'info      'white
           'muted     'white
           'accent    'white)
   
   'dracula
   (hasheq 'primary   'magenta
           'secondary 'cyan
           'success   'green
           'warning   'yellow
           'error     'red
           'info      'cyan
           'muted     'white
           'accent    'magenta)
   
   'solarized
   (hasheq 'primary   'blue
           'secondary 'cyan
           'success   'green
           'warning   'yellow
           'error     'red
           'info      'cyan
           'muted     'white
           'accent    'magenta)))

(define current-theme (make-parameter 'default))

(define (available-themes)
  (hash-keys THEMES))

(define (set-theme! theme-name)
  (if (hash-has-key? THEMES theme-name)
      (current-theme theme-name)
      (log-debug 1 'style "Unknown theme: ~a" theme-name)))

(define (theme-color role)
  (define theme (hash-ref THEMES (current-theme) (hash-ref THEMES 'default)))
  (hash-ref theme role 'white))

;; ---------------------------------------------------------------------------
;; Pre-styled Message Functions
;; ---------------------------------------------------------------------------

(define (error-message text)
  (styled (string-append "✗ " text)
          #:fg (theme-color 'error)
          #:bold? #t))

(define (success-message text)
  (styled (string-append "✓ " text)
          #:fg (theme-color 'success)
          #:bold? #t))

(define (warning-message text)
  (styled (string-append "⚠ " text)
          #:fg (theme-color 'warning)
          #:bold? #t))

(define (info-message text)
  (styled (string-append "ℹ " text)
          #:fg (theme-color 'info)))

;; ---------------------------------------------------------------------------
;; Module Initialization
;; ---------------------------------------------------------------------------

(module+ test
  (require rackunit)
  
  ;; Test color detection
  (parameterize ([color-enabled-param #t])
    (check-equal? (color 'red "test") "\033[31mtest\033[0m")
    (check-equal? (bold "test") "\033[1mtest\033[0m")
    (check-equal? (dim "test") "\033[2mtest\033[0m"))
  
  ;; Test disabled colors
  (parameterize ([color-enabled-param #f])
    (check-equal? (color 'red "test") "test")
    (check-equal? (bold "test") "test")
    (check-equal? (rainbow "abc") "abc"))
  
  ;; Test themes
  (check-not-false (member 'default (available-themes)))
  (check-not-false (member 'cyberpunk (available-themes)))
  (check-not-false (member 'dracula (available-themes))))
