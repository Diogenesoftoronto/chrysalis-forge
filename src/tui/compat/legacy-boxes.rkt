#lang racket/base
;; Legacy Message Boxes Compatibility Layer
;; Re-exports new TUI doc/style/layout with old message-boxes.rkt API

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

(require racket/string
         racket/list
         racket/format
         "../style.rkt"
         "../terminal.rkt"
         "../doc.rkt")

;; ============================================================================
;; Terminal Width
;; ============================================================================

(define DEFAULT-WIDTH 80)

(define (terminal-width)
  (define size (get-terminal-size))
  (if (pair? size) (car size) DEFAULT-WIDTH))

;; ============================================================================
;; Icons
;; ============================================================================

(define ICONS
  (hasheq 'error   "✖"
          'success "✓"
          'warning "⚠"
          'info    "ℹ"))

;; ============================================================================
;; Word Wrapping
;; ============================================================================

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

;; ============================================================================
;; Padding Helper
;; ============================================================================

(define (pad-right str width)
  (define len (string-length str))
  (if (>= len width)
      str
      (string-append str (make-string (- width len) #\space))))

;; ============================================================================
;; Box Rendering using new TUI style system
;; ============================================================================

(define (render-box lines
                    #:title [title #f]
                    #:color [color 'white]
                    #:style [box-style 'round]
                    #:width [width 60]
                    #:icon [icon #f]
                    #:suggestions [suggestions '()])
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
  
  (define border-chars
    (case box-style
      [(round rounded) rounded-border]
      [(square) square-border]
      [(double) double-border]
      [(thick) thick-border]
      [else rounded-border]))
  
  (define fg-color
    (case color
      [(bright-red) 'bright-red]
      [(bright-green) 'bright-green]
      [(bright-yellow) 'bright-yellow]
      [(bright-cyan) 'bright-cyan]
      [else color]))
  
  (define title-str
    (if title
        (let ([t (if icon (format " ~a ~a " icon title) (format " ~a " title))])
          (style-render (style-set empty-style #:fg fg-color #:bold #t) t))
        ""))
  
  (define title-display-len
    (if title
        (string-length (if icon (format " ~a ~a " icon title) (format " ~a " title)))
        0))
  
  (define border-style (style-set empty-style #:fg fg-color))
  
  (define top-bar-left 2)
  (define top-bar-right (max 0 (- width 2 title-display-len top-bar-left)))
  
  (define top-line
    (string-append
     (style-render border-style
                   (string-append (border-top-left border-chars)
                                  (make-string top-bar-left #\─)))
     title-str
     (style-render border-style
                   (string-append (make-string top-bar-right #\─)
                                  (border-top-right border-chars)))))
  
  (define body-lines
    (for/list ([line (in-list content-lines)])
      (string-append
       (style-render border-style (border-left border-chars))
       " "
       (pad-right line inner-width)
       " "
       (style-render border-style (border-right border-chars)))))
  
  (define bottom-line
    (style-render border-style
                  (string-append (border-bottom-left border-chars)
                                 (make-string (- width 2) #\─)
                                 (border-bottom-right border-chars))))
  
  (string-join (cons top-line (append body-lines (list bottom-line))) "\n"))

;; ============================================================================
;; Public API - Message Box Functions
;; ============================================================================

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

;; ============================================================================
;; Simple Print Functions
;; ============================================================================

(define (print-error message)
  (displayln (style-render (style-set empty-style #:fg 'bright-red #:bold #t)
                           (format "✖ ~a" message))))

(define (print-success message)
  (displayln (style-render (style-set empty-style #:fg 'bright-green #:bold #t)
                           (format "✓ ~a" message))))

(define (print-warning message)
  (displayln (style-render (style-set empty-style #:fg 'bright-yellow #:bold #t)
                           (format "⚠ ~a" message))))

(define (print-info message)
  (displayln (style-render (style-set empty-style #:fg 'bright-cyan #:bold #t)
                           (format "ℹ ~a" message))))

;; ============================================================================
;; Tests
;; ============================================================================

(module+ test
  (require rackunit)
  
  (test-case "terminal-width returns positive integer"
    (check-pred exact-positive-integer? (terminal-width)))
  
  (test-case "word-wrap handles empty string"
    (check-equal? (word-wrap "" 40) '("")))
  
  (test-case "word-wrap wraps long text"
    (define lines (word-wrap "hello world this is a test" 10))
    (check-true (> (length lines) 1)))
  
  (test-case "pad-right pads correctly"
    (check-equal? (string-length (pad-right "hi" 10)) 10))
  
  (test-case "render-box produces bordered output"
    (define result (render-box '("hello") #:title "Test" #:width 30))
    (check-true (string-contains? result "╭"))
    (check-true (string-contains? result "╯"))
    (check-true (string-contains? result "Test"))))
