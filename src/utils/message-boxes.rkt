#lang racket/base
(require racket/string
         racket/list
         racket/format
         racket/system
         racket/port)

(provide error-box
         success-box
         warning-box
         info-box
         message-box
         print-error
         print-success
         print-warning
         print-info
         terminal-width)

(define DEFAULT-WIDTH 80)

(define (terminal-width)
  (with-handlers ([exn:fail? (λ (_) DEFAULT-WIDTH)])
    (define output
      (with-output-to-string
        (λ () (system "tput cols 2>/dev/null || echo 80"))))
    (define parsed (string->number (string-trim output)))
    (if (and parsed (> parsed 0)) parsed DEFAULT-WIDTH)))

(define RESET "\033[0m")
(define BOLD  "\033[1m")

(define (fg color)
  (case color
    [(red)     "\033[31m"]
    [(green)   "\033[32m"]
    [(yellow)  "\033[33m"]
    [(blue)    "\033[34m"]
    [(magenta) "\033[35m"]
    [(cyan)    "\033[36m"]
    [(white)   "\033[37m"]
    [(bright-red)    "\033[91m"]
    [(bright-green)  "\033[92m"]
    [(bright-yellow) "\033[93m"]
    [(bright-cyan)   "\033[96m"]
    [else      ""]))

(define BOX-ROUND
  (hasheq 'tl "╭" 'tr "╮" 'bl "╰" 'br "╯" 'h "─" 'v "│"))

(define BOX-SQUARE
  (hasheq 'tl "┌" 'tr "┐" 'bl "└" 'br "┘" 'h "─" 'v "│"))

(define (get-box-chars style)
  (case style
    [(round rounded) BOX-ROUND]
    [else BOX-SQUARE]))

(define ICONS
  (hasheq 'error   "✖"
          'success "✓"
          'warning "⚠"
          'info    "ℹ"))

(define (word-wrap text width)
  (define words (string-split text))
  (define lines '())
  (define current-line "")
  (for ([word (in-list words)])
    (define test-line
      (if (string=? current-line "")
          word
          (string-append current-line " " word)))
    (if (<= (string-length test-line) width)
        (set! current-line test-line)
        (begin
          (unless (string=? current-line "")
            (set! lines (append lines (list current-line))))
          (set! current-line word))))
  (unless (string=? current-line "")
    (set! lines (append lines (list current-line))))
  (if (null? lines) '("") lines))

(define (pad-right str width)
  (define len (string-length str))
  (if (>= len width)
      str
      (string-append str (make-string (- width len) #\space))))

(define (render-box lines
                    #:title [title #f]
                    #:color [color 'white]
                    #:style [style 'round]
                    #:width [width 60]
                    #:icon [icon #f]
                    #:suggestions [suggestions '()])
  (define box-chars (get-box-chars style))
  (define color-code (fg color))
  (define inner-width (- width 4))
  
  (define all-lines
    (apply append
           (for/list ([line (in-list lines)])
             (word-wrap line inner-width))))
  
  (define suggestion-lines
    (if (null? suggestions)
        '()
        (cons ""
              (apply append
                     (for/list ([s (in-list suggestions)])
                       (word-wrap (format "→ ~a" s) inner-width))))))
  
  (define content-lines (append all-lines suggestion-lines))
  
  (define title-str
    (if title
        (let ([t (if icon (format " ~a ~a " icon title) (format " ~a " title))])
          (format "~a~a~a~a" BOLD color-code t RESET))
        ""))
  
  (define title-display-len
    (if title
        (+ (string-length (if icon (format " ~a ~a " icon title) (format " ~a " title))) 0)
        0))
  
  (define top-bar-left 2)
  (define top-bar-right (max 0 (- width 2 title-display-len top-bar-left)))
  
  (define top-line
    (format "~a~a~a~a~a~a~a"
            color-code
            (hash-ref box-chars 'tl)
            (make-string top-bar-left #\─)
            RESET
            title-str
            color-code
            (string-append (make-string top-bar-right #\─)
                           (hash-ref box-chars 'tr)
                           RESET)))
  
  (define body-lines
    (for/list ([line (in-list content-lines)])
      (format "~a~a~a ~a ~a~a~a"
              color-code
              (hash-ref box-chars 'v)
              RESET
              (pad-right line inner-width)
              color-code
              (hash-ref box-chars 'v)
              RESET)))
  
  (define bottom-line
    (format "~a~a~a~a"
            color-code
            (hash-ref box-chars 'bl)
            (make-string (- width 2) #\─)
            (string-append (hash-ref box-chars 'br) RESET)))
  
  (string-join (cons top-line (append body-lines (list bottom-line))) "\n"))

(define (message-box message
                     #:title [title #f]
                     #:style [style 'round]
                     #:color [color 'white]
                     #:width [width 60]
                     #:icon [icon #f]
                     #:suggestions [suggestions '()])
  (define lines (string-split message "\n"))
  (displayln (render-box lines
                         #:title title
                         #:color color
                         #:style style
                         #:width width
                         #:icon icon
                         #:suggestions suggestions)))

(define (error-box message
                   #:title [title "Error"]
                   #:suggestions [suggestions '()]
                   #:width [width 60])
  (message-box message
               #:title title
               #:color 'bright-red
               #:icon (hash-ref ICONS 'error)
               #:width width
               #:suggestions suggestions))

(define (success-box message
                     #:title [title "Success"]
                     #:icon [icon #f]
                     #:width [width 60])
  (define display-icon (or icon (hash-ref ICONS 'success)))
  (define celebration (format "~a ~a" display-icon message))
  (message-box celebration
               #:title title
               #:color 'bright-green
               #:width width))

(define (warning-box message
                     #:title [title "Warning"]
                     #:width [width 60])
  (message-box message
               #:title title
               #:color 'bright-yellow
               #:icon (hash-ref ICONS 'warning)
               #:width width))

(define (info-box message
                  #:title [title "Info"]
                  #:width [width 60])
  (message-box message
               #:title title
               #:color 'bright-cyan
               #:icon (hash-ref ICONS 'info)
               #:width width))

(define (print-error message)
  (displayln (format "~a~a✖ ~a~a" BOLD (fg 'bright-red) message RESET)))

(define (print-success message)
  (displayln (format "~a~a✓ ~a~a" BOLD (fg 'bright-green) message RESET)))

(define (print-warning message)
  (displayln (format "~a~a⚠ ~a~a" BOLD (fg 'bright-yellow) message RESET)))

(define (print-info message)
  (displayln (format "~a~aℹ ~a~a" BOLD (fg 'bright-cyan) message RESET)))
