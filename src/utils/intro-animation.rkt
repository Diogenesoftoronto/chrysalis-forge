#lang racket/base
;; Animated Startup Sequence for CLI
;; Provides multi-frame ASCII art logo animation, system check visualization,
;; and animated greeting with tips.

(provide
 play-intro!
 show-logo
 show-system-checks
 show-greeting
 ;; Raw animation data for TUI event loop
 LOGO-FRAMES
 LOGO-TITLE
 STATUS-ICONS)

(require racket/string
         racket/list
         racket/format
         "../tui/compat/legacy-style.rkt"
         "loading-animations.rkt")

;;; ============================================================================
;;; Animation Timing Constants
;;; ============================================================================

(define FRAME-DELAY-MS 150)
(define CHECK-DELAY-MS 80)
(define GREETING-CHAR-DELAY-MS 2)

;;; ============================================================================
;;; ASCII Art Logo Frames (Chrysalis/Butterfly Theme)
;;; ============================================================================

(define LOGO-FRAMES
  (list
   ;; Frame 1: Basic cocoon shape
   #<<FRAME
       ╭─────╮
      ╱ ░░░░░ ╲
     │  ░░░░░  │
     │  ░░░░░  │
      ╲ ░░░░░ ╱
       ╰─────╯
FRAME

   ;; Frame 2: Opening
   #<<FRAME
       ╭──┬──╮
      ╱ ░░│░░ ╲
     │  ░░│░░  │
     │  ░░│░░  │
      ╲ ░░│░░ ╱
       ╰──┴──╯
FRAME

   ;; Frame 3: Wings emerging
   #<<FRAME
    ╭──╮     ╭──╮
   ╱ ░░ ╲   ╱ ░░ ╲
  │  ░░  │ │  ░░  │
   ╲ ░░ ╱   ╲ ░░ ╱
    ╰──╯     ╰──╯
FRAME

   ;; Frame 4: Full butterfly/chrysalis
   #<<FRAME
   ╭────╮   ╭────╮
  ╱ ▓▓▓▓ ╲ ╱ ▓▓▓▓ ╲
 │  ▓▓▓▓  ╳  ▓▓▓▓  │
  ╲ ▓▓▓▓ ╱ ╲ ▓▓▓▓ ╱
   ╰────╯   ╰────╯
FRAME
   ))

(define LOGO-TITLE
  #<<TITLE
   ╔═╗╦ ╦╦═╗╦ ╦╔═╗╔═╗╦  ╦╔═╗
   ║  ╠═╣╠╦╝╚╦╝╚═╗╠═╣║  ║╚═╗
   ╚═╝╩ ╩╩╚═ ╩ ╚═╝╩ ╩╩═╝╩╚═╝
            ╔═╗╔═╗╦═╗╔═╗╔═╗
            ╠╣ ║ ║╠╦╝║ ╦║╣
            ╚  ╚═╝╩╚═╚═╝╚═╝
TITLE
  )

;;; ============================================================================
;;; Status Indicators
;;; ============================================================================

(define STATUS-ICONS
  (hasheq 'ok      "✓"
          'fail    "✗"
          'warn    "⚠"
          'skip    "○"
          'pending "◌"))

(define (status-icon status)
  (hash-ref STATUS-ICONS status "?"))

(define (status-color status)
  (case status
    [(ok)      'green]
    [(fail)    'red]
    [(warn)    'yellow]
    [(skip)    'white]
    [(pending) 'cyan]
    [else      'white]))

;;; ============================================================================
;;; Animation Helpers
;;; ============================================================================

(define (clear-lines n [port (current-output-port)])
  (for ([_ (in-range n)])
    (fprintf port "\033[A\033[K")))

(define (frame-line-count frame)
  (length (string-split frame "\n")))

(define (print-frame frame #:color [col 'cyan] [port (current-output-port)])
  (define lines (string-split frame "\n"))
  (for ([line (in-list lines)])
    (displayln (color col line) port))
  (flush-output port))

(define (animate-frames frames #:delay-ms [delay-ms FRAME-DELAY-MS]
                        #:color [col 'cyan]
                        #:port [port (current-output-port)])
  (define max-lines (apply max (map frame-line-count frames)))

  (for ([frame (in-list frames)]
        [i (in-naturals)])
    (when (> i 0)
      (clear-lines max-lines port))
    (print-frame frame #:color col port)
    (define pad-lines (- max-lines (frame-line-count frame)))
    (for ([_ (in-range pad-lines)])
      (newline port))
    (sleep (/ delay-ms 1000.0))))

(define (typewriter-print text #:delay-ms [delay-ms GREETING-CHAR-DELAY-MS]
                          #:port [port (current-output-port)])
  (for ([char (in-string text)])
    (display char port)
    (flush-output port)
    (sleep (/ delay-ms 1000.0)))
  (newline port))

;;; ============================================================================
;;; Public API
;;; ============================================================================

(define (show-logo #:animated? [animated? #t]
                   #:port [port (current-output-port)])
  (if animated?
      (begin
        (animate-frames LOGO-FRAMES #:color 'magenta #:port port)
        (newline port)
        (for ([line (in-list (string-split LOGO-TITLE "\n"))])
          (displayln (gradient line 'cyan 'magenta) port)
          (sleep 0.03))
        (flush-output port))
      (begin
        (print-frame (last LOGO-FRAMES) #:color 'magenta port)
        (newline port)
        (for ([line (in-list (string-split LOGO-TITLE "\n"))])
          (displayln (color 'cyan line) port))
        (flush-output port))))

(define (show-system-checks checks-list
                            #:port [port (current-output-port)])
  (displayln (bold (color 'cyan "  System Checks")) port)
  (displayln "" port)

  (for ([check (in-list checks-list)])
    (define name (car check))
    (define status (cdr check))
    (define icon (status-icon status))
    (define col (status-color status))

    ;; Show pending first
    (fprintf port "    ~a ~a... "
             (color 'cyan (status-icon 'pending))
             (dim name))
    (flush-output port)
    (sleep (/ CHECK-DELAY-MS 1000.0))

    ;; Clear and show result
    (fprintf port "\r\033[K    ~a ~a~n"
             (color col icon)
             (if (eq? status 'ok)
                 name
                 (color col name)))
    (flush-output port))

  (displayln "" port))

(define (show-greeting #:tip [tip #f]
                       #:animated? [animated? #t]
                       #:port [port (current-output-port)])
  (define greeting "Welcome to Chrysalis Forge")
  (define formatted-greeting (bold (gradient greeting 'cyan 'magenta)))

  (displayln "" port)
  (if animated?
      (begin
        (display "  " port)
        (typewriter-print formatted-greeting #:port port))
      (displayln (string-append "  " formatted-greeting) port))

  (when tip
    (displayln "" port)
    (displayln (string-append "  " (dim "💡 Tip: ") (italic tip)) port))

  (displayln "" port)
  (flush-output port))

(define (play-intro! #:fast? [fast? #f]
                     #:skip-checks? [skip-checks? #f]
                     #:checks [checks '()]
                     #:tip [tip #f]
                     #:port [port (current-output-port)])
  (if fast?
      ;; Fast mode: skip animations
      (begin
        (show-logo #:animated? #f #:port port)
        (unless skip-checks?
          (when (not (null? checks))
            (displayln (bold (color 'cyan "  System Checks")) port)
            (for ([check (in-list checks)])
              (define name (car check))
              (define status (cdr check))
              (displayln (format "    ~a ~a"
                                 (color (status-color status) (status-icon status))
                                 name)
                         port))
            (displayln "" port)))
        (show-greeting #:tip tip #:animated? #f #:port port))
      ;; Full animated intro
      (begin
        (show-logo #:animated? #t #:port port)
        (unless skip-checks?
          (when (not (null? checks))
            (show-system-checks checks #:port port)))
        (show-greeting #:tip tip #:animated? #t #:port port))))

;;; ============================================================================
;;; Module Tests
;;; ============================================================================

(module+ test
  (require rackunit
           racket/port)

  ;; Test status icons
  (check-equal? (status-icon 'ok) "✓")
  (check-equal? (status-icon 'fail) "✗")
  (check-equal? (status-icon 'warn) "⚠")

  ;; Test status colors
  (check-equal? (status-color 'ok) 'green)
  (check-equal? (status-color 'fail) 'red)

  ;; Test frame line count
  (check-equal? (frame-line-count "a\nb\nc") 3)
  (check-equal? (frame-line-count "single") 1)

  ;; Test that play-intro! produces output (fast mode, no animations)
  (parameterize ([color-enabled-param #f])
    (define output
      (with-output-to-string
        (λ ()
          (play-intro! #:fast? #t
                       #:skip-checks? #t
                       #:tip "Test tip"))))
    (check-true (string-contains? output "╔═╗╦ ╦╦═╗"))  ; Part of CHRYSALIS banner
    (check-true (string-contains? output "Welcome"))
    (check-true (string-contains? output "Test tip"))))
