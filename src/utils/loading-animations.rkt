#lang racket/base

(provide start-spinner!
         stop-spinner!
         with-spinner
         make-progress-bar
         progress-bar-update!
         progress-bar-finish!
         SPINNER-STYLES)

(require racket/list
         racket/format
         racket/match
         racket/string)

;;; ============================================================================
;;; ANSI Color Helpers
;;; ============================================================================

(define (ansi-code . codes)
  (format "\033[~am" (string-join (map number->string codes) ";")))

(define RESET (ansi-code 0))
(define BOLD (ansi-code 1))
(define DIM (ansi-code 2))
(define CYAN (ansi-code 36))
(define GREEN (ansi-code 32))
(define YELLOW (ansi-code 33))

;;; ============================================================================
;;; Spinner Styles
;;; ============================================================================

(define SPINNER-STYLES
  (hasheq
   'dots    '("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
   'blocks  '("▏" "▎" "▍" "▌" "▋" "▊" "▉" "█" "▉" "▊" "▋" "▌" "▍" "▎")
   'arrows  '("←" "↖" "↑" "↗" "→" "↘" "↓" "↙")
   'clock   '("🕐" "🕑" "🕒" "🕓" "🕔" "🕕" "🕖" "🕗" "🕘" "🕙" "🕚" "🕛")
   'bounce  '("⠁" "⠂" "⠄" "⠂")
   'line    '("-" "\\" "|" "/")
   'circle  '("◐" "◓" "◑" "◒")
   'square  '("◰" "◳" "◲" "◱")
   'star    '("✶" "✸" "✹" "✺" "✹" "✸")
   'pulse   '("█" "▓" "▒" "░" "▒" "▓")))

;;; ============================================================================
;;; Named Spinner Registry
;;; ============================================================================

(define spinner-registry (make-hash))
(define registry-lock (make-semaphore 1))

(define (register-spinner! id thread)
  (call-with-semaphore registry-lock
    (λ () (hash-set! spinner-registry id thread))))

(define (unregister-spinner! id)
  (call-with-semaphore registry-lock
    (λ () (hash-remove! spinner-registry id))))

(define (lookup-spinner id)
  (call-with-semaphore registry-lock
    (λ () (hash-ref spinner-registry id #f))))

;;; ============================================================================
;;; Spinner Implementation
;;; ============================================================================

(define (start-spinner! label #:style [style 'dots] #:id [id #f])
  (define frames (hash-ref SPINNER-STYLES style (hash-ref SPINNER-STYLES 'dots)))
  (define out (current-error-port))
  (define spinner-id (or id (gensym 'spinner)))
  
  (define t
    (thread
     (λ ()
       (let loop ([frames-remaining frames])
         (define frame (if (null? frames-remaining)
                           (first frames)
                           (first frames-remaining)))
         (define next-frames (if (null? frames-remaining)
                                 (rest frames)
                                 (if (null? (rest frames-remaining))
                                     frames
                                     (rest frames-remaining))))
         
         (fprintf out "\r\033[K~a~a~a ~a" CYAN frame RESET label)
         (flush-output out)
         
         (sleep 0.08)
         (loop next-frames)))))
  
  (register-spinner! spinner-id t)
  (values t spinner-id))

(define (stop-spinner! thread-or-id #:success [success #t])
  (define t
    (cond
      [(thread? thread-or-id) thread-or-id]
      [else (lookup-spinner thread-or-id)]))
  
  (when (and t (thread? t))
    (kill-thread t)
    (when (not (thread? thread-or-id))
      (unregister-spinner! thread-or-id))
    (define out (current-error-port))
    (fprintf out "\r\033[K")
    (when success
      (fprintf out "~a✓~a " GREEN RESET))
    (flush-output out)))

(define-syntax-rule (with-spinner label body ...)
  (let-values ([(t id) (start-spinner! label)])
    (dynamic-wind
      void
      (λ () body ...)
      (λ () (stop-spinner! t)))))

;;; ============================================================================
;;; Progress Bar
;;; ============================================================================

(struct progress-bar (total label width style current-box lock out) #:mutable)

(define (make-progress-bar total
                           #:label [label "Loading"]
                           #:width [width 40]
                           #:style [style 'blocks])
  (define pb (progress-bar total label width style (box 0) (make-semaphore 1) (current-error-port)))
  (progress-bar-render! pb)
  pb)

(define (progress-bar-update! pb current)
  (call-with-semaphore (progress-bar-lock pb)
    (λ ()
      (set-box! (progress-bar-current-box pb) current)
      (progress-bar-render! pb))))

(define (progress-bar-finish! pb)
  (call-with-semaphore (progress-bar-lock pb)
    (λ ()
      (set-box! (progress-bar-current-box pb) (progress-bar-total pb))
      (progress-bar-render! pb #:finished #t))))

(define (progress-bar-render! pb #:finished [finished #f])
  (define current (unbox (progress-bar-current-box pb)))
  (define total (progress-bar-total pb))
  (define width (progress-bar-width pb))
  (define label (progress-bar-label pb))
  (define out (progress-bar-out pb))
  (define style (progress-bar-style pb))
  
  (define ratio (if (zero? total) 1.0 (/ current total)))
  (define percent (exact->inexact (* 100 ratio)))
  (define filled-width (inexact->exact (round (* width ratio))))
  (define empty-width (- width filled-width))
  
  (define fill-char (if (eq? style 'blocks) "▓" "█"))
  (define empty-char "░")
  
  (define bar-str
    (string-append
     (make-string filled-width (string-ref fill-char 0))
     (make-string empty-width (string-ref empty-char 0))))
  
  (fprintf out "\r\033[K~a~a~a │~a~a~a│ ~a~a~5,1f%~a"
           (if finished GREEN CYAN)
           label
           RESET
           (if finished GREEN YELLOW)
           bar-str
           RESET
           BOLD
           (if finished GREEN "")
           percent
           RESET)
  
  (when finished
    (fprintf out " ~a✓~a\n" GREEN RESET))
  
  (flush-output out))
