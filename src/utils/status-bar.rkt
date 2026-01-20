#lang racket/base
;; Persistent Status Bar for CLI
;; Displays key metrics at the bottom of the terminal with real-time updates.

(provide
 status-bar-visible?
 status-bar-show!
 status-bar-hide!
 status-bar-update!
 status-bar-set-field!
 with-status-bar)

(require racket/format
         racket/string
         "terminal-style.rkt")

;; ---------------------------------------------------------------------------
;; ANSI Escape Codes for Cursor/Screen Control
;; ---------------------------------------------------------------------------

(define ESC "\033")
(define CSI "\033[")

(define (save-cursor) (string-append ESC "7"))
(define (restore-cursor) (string-append ESC "8"))
(define (move-to-row row) (format "~a~a;1H" CSI row))
(define (clear-line) (string-append CSI "2K"))
(define (scroll-region top bottom) (format "~a~a;~ar" CSI top bottom))
(define (reset-scroll-region) (string-append CSI "r"))
(define (get-terminal-size)
  (define rows (or (string->number (or (getenv "LINES") "")) 24))
  (define cols (or (string->number (or (getenv "COLUMNS") "")) 80))
  (values rows cols))

;; ---------------------------------------------------------------------------
;; Status Bar State
;; ---------------------------------------------------------------------------

(define status-bar-visible? (make-parameter #f))

(define current-fields
  (make-parameter
   (hasheq 'session #f
           'model #f
           'cost 0.0
           'tokens 0
           'mode 'ask
           'thread #f)))

;; ---------------------------------------------------------------------------
;; Field Formatting
;; ---------------------------------------------------------------------------

(define (format-cost c)
  (cond
    [(not c) "-"]
    [(< c 0.01) "<$0.01"]
    [else (format "$~a" (~r c #:precision '(= 2)))]))

(define (format-tokens t)
  (cond
    [(not t) "-"]
    [(>= t 1000000) (format "~aM" (~r (/ t 1000000.0) #:precision '(= 1)))]
    [(>= t 1000) (format "~ak" (~r (/ t 1000.0) #:precision '(= 1)))]
    [else (number->string t)]))

(define (format-field field value)
  (case field
    [(session) (if value (format "Session: ~a" value) #f)]
    [(model) (if value (format "Model: ~a" value) #f)]
    [(cost) (format-cost value)]
    [(tokens) (format "~a tokens" (format-tokens value))]
    [(mode) (if value (symbol->string value) "ask")]
    [(thread) (if value (format "Thread: ~a" value) #f)]
    [else #f]))

;; ---------------------------------------------------------------------------
;; Bar Rendering
;; ---------------------------------------------------------------------------

(define (render-status-bar)
  (define fields (current-fields))
  (define parts
    (filter
     values
     (list
      (format-field 'session (hash-ref fields 'session #f))
      (format-field 'model (hash-ref fields 'model #f))
      (format-field 'cost (hash-ref fields 'cost 0.0))
      (format-field 'tokens (hash-ref fields 'tokens 0))
      (format-field 'mode (hash-ref fields 'mode 'ask))
      (format-field 'thread (hash-ref fields 'thread #f)))))
  (define content (string-join parts " │ "))
  (styled (string-append "│ " content " │")
          #:fg 'cyan
          #:bg 'black
          #:bold? #t))

(define (draw-status-bar!)
  (when (status-bar-visible?)
    (define-values (rows cols) (get-terminal-size))
    (define bar (render-status-bar))
    (define padded-bar
      (string-append bar (make-string (max 0 (- cols (string-length bar))) #\space)))
    (display (save-cursor))
    (display (move-to-row rows))
    (display (clear-line))
    (display padded-bar)
    (display (restore-cursor))
    (flush-output)))

;; ---------------------------------------------------------------------------
;; Public API
;; ---------------------------------------------------------------------------

(define (status-bar-show!)
  (unless (status-bar-visible?)
    (status-bar-visible? #t)
    (define-values (rows cols) (get-terminal-size))
    (display (scroll-region 1 (sub1 rows)))
    (draw-status-bar!)
    (flush-output)))

(define (status-bar-hide!)
  (when (status-bar-visible?)
    (status-bar-visible? #f)
    (define-values (rows cols) (get-terminal-size))
    (display (move-to-row rows))
    (display (clear-line))
    (display (reset-scroll-region))
    (flush-output)))

(define (status-bar-update! #:session-id [session-id #f]
                            #:model [model #f]
                            #:cost [cost #f]
                            #:tokens [tokens #f]
                            #:mode [mode #f]
                            #:thread [thread #f])
  (define fields (current-fields))
  (current-fields
   (hash-set*
    fields
    'session (or session-id (hash-ref fields 'session #f))
    'model (or model (hash-ref fields 'model #f))
    'cost (or cost (hash-ref fields 'cost 0.0))
    'tokens (or tokens (hash-ref fields 'tokens 0))
    'mode (or mode (hash-ref fields 'mode 'ask))
    'thread (or thread (hash-ref fields 'thread #f))))
  (draw-status-bar!))

(define (status-bar-set-field! field value)
  (current-fields (hash-set (current-fields) field value))
  (draw-status-bar!))

(define-syntax-rule (with-status-bar body ...)
  (dynamic-wind
   status-bar-show!
   (λ () body ...)
   status-bar-hide!))

;; ---------------------------------------------------------------------------
;; Tests
;; ---------------------------------------------------------------------------

(module+ test
  (require rackunit)
  
  (check-equal? (format-cost 0.0) "<$0.01")
  (check-equal? (format-cost 0.05) "$0.05")
  (check-equal? (format-cost 1.234) "$1.23")
  
  (check-equal? (format-tokens 0) "0")
  (check-equal? (format-tokens 500) "500")
  (check-equal? (format-tokens 1200) "1.2k")
  (check-equal? (format-tokens 1500000) "1.5M")
  
  (check-equal? (format-field 'mode 'code) "code")
  (check-equal? (format-field 'session "abc123") "Session: abc123")
  (check-false (format-field 'session #f)))
