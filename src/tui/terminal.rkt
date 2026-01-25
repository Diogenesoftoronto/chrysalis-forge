#lang racket/base
(provide enter-raw-mode! exit-raw-mode!
         enter-alt-screen! exit-alt-screen!
         show-cursor! hide-cursor!
         enable-bracketed-paste! disable-bracketed-paste!
         enable-mouse! disable-mouse!
         get-terminal-size
         term-write! term-flush!
         csi sgr cursor-to clear-screen clear-line
         with-raw-mode with-alt-screen
         terminal-available?)

(require racket/system racket/port racket/string racket/format)

;; ============================================================================
;; Terminal State
;; ============================================================================

(define saved-stty-settings (make-parameter #f))
(define output-buffer (make-parameter (open-output-bytes)))

(define (terminal-available?)
  (and (terminal-port? (current-input-port))
       (terminal-port? (current-output-port))))

;; ============================================================================
;; Raw Mode (stty)
;; ============================================================================

(define (get-stty-settings)
  (if (terminal-available?)
      (let ()
        (define out (open-output-string))
        (parameterize ([current-output-port out])
          (system "stty -g 2>/dev/null"))
        (string-trim (get-output-string out)))
      ""))

(define (restore-stty-settings! settings)
  (when (and (terminal-available?) settings (non-empty-string? settings))
    (system (format "stty '~a' 2>/dev/null" settings))))

(define (enter-raw-mode!)
  (when (terminal-available?)
    (unless (saved-stty-settings)
      (saved-stty-settings (get-stty-settings)))
    (system "stty raw -echo 2>/dev/null"))
  (void))

(define (exit-raw-mode!)
  (define settings (saved-stty-settings))
  (when settings
    (restore-stty-settings! settings)
    (saved-stty-settings #f))
  (void))

;; ============================================================================
;; Alternate Screen
;; ============================================================================

(define (enter-alt-screen!)
  (when (terminal-available?)
    (display "\e[?1049h")
    (flush-output)))

(define (exit-alt-screen!)
  (when (terminal-available?)
    (display "\e[?1049l")
    (flush-output)))

;; ============================================================================
;; Cursor Visibility
;; ============================================================================

(define (show-cursor!)
  (when (terminal-available?)
    (display "\e[?25h")
    (flush-output)))

(define (hide-cursor!)
  (when (terminal-available?)
    (display "\e[?25l")
    (flush-output)))

;; ============================================================================
;; Bracketed Paste Mode
;; ============================================================================

(define (enable-bracketed-paste!)
  (when (terminal-available?)
    (display "\e[?2004h")
    (flush-output)))

(define (disable-bracketed-paste!)
  (when (terminal-available?)
    (display "\e[?2004l")
    (flush-output)))

;; ============================================================================
;; Mouse Mode (Basic - X10 compatible)
;; ============================================================================

(define (enable-mouse!)
  (when (terminal-available?)
    (display "\e[?1000h")  ; Basic mouse tracking
    (display "\e[?1006h")  ; SGR extended mode for coordinates > 223
    (flush-output)))

(define (disable-mouse!)
  (when (terminal-available?)
    (display "\e[?1006l")
    (display "\e[?1000l")
    (flush-output)))

;; ============================================================================
;; Terminal Size
;; ============================================================================

(define (get-terminal-size)
  (define (try-tput)
    (and (terminal-available?)
         (with-handlers ([exn:fail? (λ (_) #f)])
           (define lines-out (open-output-string))
           (define cols-out (open-output-string))
           (parameterize ([current-output-port lines-out])
             (system "tput lines 2>/dev/null"))
           (parameterize ([current-output-port cols-out])
             (system "tput cols 2>/dev/null"))
           (define lines (string->number (string-trim (get-output-string lines-out))))
           (define cols (string->number (string-trim (get-output-string cols-out))))
           (and lines cols (cons cols lines)))))
  
  (define (try-env)
    (define cols (getenv "COLUMNS"))
    (define lines (getenv "LINES"))
    (and cols lines
         (let ([c (string->number cols)]
               [l (string->number lines)])
           (and c l (cons c l)))))
  
  (or (try-tput)
      (try-env)
      (cons 80 24)))

;; ============================================================================
;; Buffered Output
;; ============================================================================

(define (term-write! str)
  (display str (output-buffer)))

(define (term-flush!)
  (define buf (output-buffer))
  (define bytes (get-output-bytes buf #t))
  (write-bytes bytes)
  (flush-output)
  (output-buffer (open-output-bytes)))

;; ============================================================================
;; CSI Escape Code Helpers
;; ============================================================================

(define (csi . parts)
  (string-append "\e[" (string-join (map ~a parts) "")))

(define (sgr . codes)
  (csi (string-join (map ~a codes) ";") "m"))

(define (cursor-to row col)
  (csi row ";" col "H"))

(define (clear-screen [mode 2])
  (csi mode "J"))

(define (clear-line [mode 2])
  (csi mode "K"))

;; ============================================================================
;; Context Managers
;; ============================================================================

(define-syntax-rule (with-raw-mode body ...)
  (dynamic-wind
    enter-raw-mode!
    (λ () body ...)
    exit-raw-mode!))

(define-syntax-rule (with-alt-screen body ...)
  (dynamic-wind
    enter-alt-screen!
    (λ () body ...)
    exit-alt-screen!))

;; ============================================================================
;; Tests
;; ============================================================================

(module+ test
  (require rackunit)
  
  (test-case "csi generates correct escape sequences"
    (check-equal? (csi "2" "J") "\e[2J")
    (check-equal? (csi "1" ";" "1" "H") "\e[1;1H"))
  
  (test-case "sgr generates correct sequences"
    (check-equal? (sgr 0) "\e[0m")
    (check-equal? (sgr 1 31) "\e[1;31m"))
  
  (test-case "cursor-to generates correct sequence"
    (check-equal? (cursor-to 1 1) "\e[1;1H")
    (check-equal? (cursor-to 10 20) "\e[10;20H"))
  
  (test-case "clear-screen generates correct sequence"
    (check-equal? (clear-screen) "\e[2J")
    (check-equal? (clear-screen 0) "\e[0J"))
  
  (test-case "clear-line generates correct sequence"
    (check-equal? (clear-line) "\e[2K")
    (check-equal? (clear-line 1) "\e[1K"))
  
  (test-case "get-terminal-size returns valid dimensions"
    (define size (get-terminal-size))
    (check-pred pair? size)
    (check-pred exact-positive-integer? (car size))
    (check-pred exact-positive-integer? (cdr size)))
  
  (test-case "term-write! and term-flush! work with buffer"
    (parameterize ([output-buffer (open-output-bytes)])
      (term-write! "hello")
      (term-write! " world")
      (define buf (output-buffer))
      (check-equal? (get-output-bytes buf #f) #"hello world"))))