#lang racket/base
;; Legacy Style Compatibility Layer
;; Re-exports new TUI style system with old terminal-style.rkt API

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
         "../style.rkt")

;; ============================================================================
;; Color Support Detection
;; ============================================================================

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

;; ============================================================================
;; Theme System
;; ============================================================================

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
  (when (hash-has-key? THEMES theme-name)
    (current-theme theme-name)))

(define (theme-color role)
  (define theme (hash-ref THEMES (current-theme) (hash-ref THEMES 'default)))
  (hash-ref theme role 'white))

;; ============================================================================
;; Core Styling - Map to new TUI style system
;; ============================================================================

(define (color col text)
  (if (color-enabled-param)
      (style-render (style-set empty-style #:fg col) text)
      text))

(define (bright-color col text)
  (define bright-col
    (case col
      [(black)   'bright-black]
      [(red)     'bright-red]
      [(green)   'bright-green]
      [(yellow)  'bright-yellow]
      [(blue)    'bright-blue]
      [(magenta) 'bright-magenta]
      [(cyan)    'bright-cyan]
      [(white)   'bright-white]
      [else col]))
  (if (color-enabled-param)
      (style-render (style-set empty-style #:fg bright-col) text)
      text))

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
  (if (not (color-enabled-param))
      text
      (let* ([actual-fg (and fg
                             (if bright-fg?
                                 (case fg
                                   [(black)   'bright-black]
                                   [(red)     'bright-red]
                                   [(green)   'bright-green]
                                   [(yellow)  'bright-yellow]
                                   [(blue)    'bright-blue]
                                   [(magenta) 'bright-magenta]
                                   [(cyan)    'bright-cyan]
                                   [(white)   'bright-white]
                                   [else fg])
                                 fg))]
             [actual-bg (and bg
                             (if bright-bg?
                                 (case bg
                                   [(black)   'bright-black]
                                   [(red)     'bright-red]
                                   [(green)   'bright-green]
                                   [(yellow)  'bright-yellow]
                                   [(blue)    'bright-blue]
                                   [(magenta) 'bright-magenta]
                                   [(cyan)    'bright-cyan]
                                   [(white)   'bright-white]
                                   [else bg])
                                 bg))]
             [s (style-set empty-style
                           #:fg actual-fg
                           #:bg actual-bg
                           #:bold bold?
                           #:dim dim?
                           #:italic italic?
                           #:underline underline?
                           #:blink blink?
                           #:strikethrough strikethrough?)])
        (style-render s text))))

;; ============================================================================
;; Text Formatting Shortcuts
;; ============================================================================

(define (bold text)
  (if (color-enabled-param)
      (style-render (style-set empty-style #:bold #t) text)
      text))

(define (dim text)
  (if (color-enabled-param)
      (style-render (style-set empty-style #:dim #t) text)
      text))

(define (italic text)
  (if (color-enabled-param)
      (style-render (style-set empty-style #:italic #t) text)
      text))

(define (underline text)
  (if (color-enabled-param)
      (style-render (style-set empty-style #:underline #t) text)
      text))

(define (blink text)
  (if (color-enabled-param)
      (style-render (style-set empty-style #:blink #t) text)
      text))

(define (strikethrough text)
  (if (color-enabled-param)
      (style-render (style-set empty-style #:strikethrough #t) text)
      text))

(define (reset-style)
  (if (color-enabled-param) "\e[0m" ""))

;; ============================================================================
;; Text Effects
;; ============================================================================

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

(define COLOR-RGB
  (hasheq 'black   '(0 0 0)
          'red     '(255 0 0)
          'green   '(0 255 0)
          'yellow  '(255 255 0)
          'blue    '(0 0 255)
          'magenta '(255 0 255)
          'cyan    '(0 255 255)
          'white   '(255 255 255)))

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
                     (define hex-color
                       (format "#~a~a~a"
                               (~r (first rgb) #:base 16 #:min-width 2 #:pad-string "0")
                               (~r (second rgb) #:base 16 #:min-width 2 #:pad-string "0")
                               (~r (third rgb) #:base 16 #:min-width 2 #:pad-string "0")))
                     (style-render (style-set empty-style #:fg hex-color)
                                   (string c))))))))

(require racket/format)

;; ============================================================================
;; Pre-styled Message Functions
;; ============================================================================

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

;; ============================================================================
;; Tests
;; ============================================================================

(module+ test
  (require rackunit)
  
  (parameterize ([color-enabled-param #t])
    (check-true (string-contains? (color 'red "test") "\e[31m"))
    (check-true (string-contains? (bold "test") "\e[1m"))
    (check-true (string-contains? (dim "test") "\e[2m")))
  
  (parameterize ([color-enabled-param #f])
    (check-equal? (color 'red "test") "test")
    (check-equal? (bold "test") "test")
    (check-equal? (rainbow "abc") "abc"))
  
  (check-not-false (member 'default (available-themes)))
  (check-not-false (member 'cyberpunk (available-themes)))
  (check-not-false (member 'dracula (available-themes))))
