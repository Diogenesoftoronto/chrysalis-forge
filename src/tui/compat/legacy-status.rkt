#lang racket/base
;; Legacy Status Bar Compatibility Layer
;; Re-exports status bar using new TUI terminal and style system

(provide
 status-bar-visible?
 status-bar-show!
 status-bar-hide!
 status-bar-update!
 status-bar-set-field!
 with-status-bar)

(require racket/format
         racket/string
         "../style.rkt"
         "../terminal.rkt")

;; ============================================================================
;; ANSI Escape Codes for Cursor/Screen Control
;; ============================================================================

(define ESC "\033")

(define (save-cursor) (string-append ESC "7"))
(define (restore-cursor) (string-append ESC "8"))
(define (move-to-row row) (csi row ";" 1 "H"))
(define (scroll-region top bottom) (format "\033[~a;~ar" top bottom))
(define (reset-scroll-region) "\033[r")

(define (get-term-size)
  (define size (get-terminal-size))
  (if (pair? size)
      (values (cdr size) (car size))
      (values 24 80)))

;; ============================================================================
;; Status Bar State
;; ============================================================================

(define status-bar-visible? (make-parameter #f))

(define current-fields
  (make-parameter
   (hasheq 'session #f
           'model #f
           'cost 0.0
           'tokens 0
           'mode 'ask
           'thread #f)))

;; ============================================================================
;; Field Formatting
;; ============================================================================

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

;; ============================================================================
;; Bar Rendering using new TUI style system
;; ============================================================================

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
  (style-render (style-set empty-style
                           #:fg 'cyan
                           #:bg 'black
                           #:bold #t)
                (string-append "│ " content " │")))

(define (draw-status-bar!)
  (when (status-bar-visible?)
    (define-values (rows cols) (get-term-size))
    (define bar (render-status-bar))
    (define padded-bar
      (string-append bar (make-string (max 0 (- cols (string-length bar))) #\space)))
    (display (save-cursor))
    (display (move-to-row rows))
    (display (clear-line))
    (display padded-bar)
    (display (restore-cursor))
    (flush-output)))

;; ============================================================================
;; Public API
;; ============================================================================

(define (status-bar-show!)
  (unless (status-bar-visible?)
    (status-bar-visible? #t)
    (define-values (rows cols) (get-term-size))
    (display (scroll-region 1 (sub1 rows)))
    (draw-status-bar!)
    (flush-output)))

(define (status-bar-hide!)
  (when (status-bar-visible?)
    (status-bar-visible? #f)
    (define-values (rows cols) (get-term-size))
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

;; ============================================================================
;; Tests
;; ============================================================================

(module+ test
  (require rackunit)
  
  (test-case "format-cost handles edge cases"
    (check-equal? (format-cost 0.0) "<$0.01")
    (check-equal? (format-cost 0.05) "$0.05")
    (check-equal? (format-cost 1.234) "$1.23"))
  
  (test-case "format-tokens handles ranges"
    (check-equal? (format-tokens 0) "0")
    (check-equal? (format-tokens 500) "500")
    (check-equal? (format-tokens 1200) "1.2k")
    (check-equal? (format-tokens 1500000) "1.5M"))
  
  (test-case "format-field handles modes"
    (check-equal? (format-field 'mode 'code) "code")
    (check-equal? (format-field 'session "abc123") "Session: abc123")
    (check-false (format-field 'session #f)))
  
  (test-case "render-status-bar produces styled output"
    (parameterize ([current-fields (hasheq 'mode 'ask 'cost 0.0 'tokens 100)])
      (define bar (render-status-bar))
      (check-true (string-contains? bar "tokens"))
      (check-true (string-contains? bar "\e[")))))
