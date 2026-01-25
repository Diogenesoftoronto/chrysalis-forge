#lang racket/base
(provide (struct-out program)
         (struct-out size)
         (struct-out rect)
         (struct-out quit-msg)
         (struct-out resize-msg)
         (struct-out cmd)
         run-program
         cmd? cmd-or-none? none batch quit send-msg
         current-program-channel)

(require racket/match racket/port racket/async-channel racket/list
         "terminal.rkt"
         "input/parse.rkt")

;; ============================================================================
;; Structs
;; ============================================================================

(struct program (init update view [opts #:auto])
  #:auto-value '()
  #:transparent)

(struct size (width height) #:transparent)
(struct rect (x y width height) #:transparent)

;; Message types
(struct quit-msg () #:transparent)
(struct resize-msg (size) #:transparent)

;; ============================================================================
;; Commands
;; ============================================================================

(struct cmd (thunk) #:transparent)

(define (cmd-or-none? v)
  (or (cmd? v) (eq? v 'none) (and (list? v) (andmap cmd-or-none? v))))

(define none 'none)

(define (batch . cmds)
  (filter cmd? (flatten cmds)))

(define (quit)
  (cmd (λ (ch) (async-channel-put ch (quit-msg)))))

(define (send-msg msg)
  (cmd (λ (ch) (async-channel-put ch msg))))

;; ============================================================================
;; Program State
;; ============================================================================

(define current-program-channel (make-parameter #f))

;; ============================================================================
;; Event Loop
;; ============================================================================

(define (execute-cmd! cmd ch)
  (when (cmd? cmd)
    (cond
      [(eq? cmd 'none) (void)]
      [(list? cmd) (for-each (λ (c) (execute-cmd! c ch)) cmd)]
      [else
       (thread (λ () ((cmd-thunk cmd) ch)))])))

(define (read-byte-with-timeout port timeout-ms)
  (sync/timeout (/ timeout-ms 1000.0)
                (handle-evt (read-bytes-evt 1 port)
                            (λ (bs) (and bs (bytes-ref bs 0))))))

(define (run-program prog
                     #:input [input-port (current-input-port)]
                     #:output [output-port (current-output-port)]
                     #:alt-screen? [alt-screen? #t]
                     #:mouse? [mouse? #f]
                     #:bracketed-paste? [bracketed-paste? #f])
  (define msg-channel (make-async-channel))

  (define (setup!)
    (enter-raw-mode!)
    (when alt-screen? (enter-alt-screen!))
    (hide-cursor!)
    (when mouse? (enable-mouse!))
    (when bracketed-paste? (enable-bracketed-paste!)))

  (define (teardown!)
    (when bracketed-paste? (disable-bracketed-paste!))
    (when mouse? (disable-mouse!))
    (show-cursor!)
    (when alt-screen? (exit-alt-screen!))
    (exit-raw-mode!))

  (define (render! model view-fn out-port)
    (define term-size (get-terminal-size))
    (define sz (size (car term-size) (cdr term-size)))
    (define view-str (view-fn model sz))
    (parameterize ([current-output-port out-port])
      (term-write! (cursor-to 1 1))
      (term-write! (clear-screen))
      (term-write! view-str)
      (term-flush!)))

  ;; Input reader thread with parser
  (define (start-input-reader!)
    (thread
     (λ ()
       (define parser (make-input-parser))
       (let loop ()
         (define b (read-byte input-port))
         (unless (eof-object? b)
           ;; Parse the byte into events
           (define events (parse-input parser (bytes b)))
           (for ([evt (in-list events)])
             (async-channel-put msg-channel evt))
           (loop))))))

  ;; SIGWINCH handler (Unix resize signal)
  (define (install-resize-handler!)
    (with-handlers ([exn:fail? void])
      (define (handle-winch _sig)
        (define term-size (get-terminal-size))
        (async-channel-put msg-channel
                           (resize-msg (size (car term-size) (cdr term-size)))))
      ;; Try to install signal handler if available
      (when (member 'unix (system-type 'os*))
        (unsafe-register-signal-handler! 28 handle-winch))))

  (define (unsafe-register-signal-handler! sig handler)
    ;; Racket doesn't have direct SIGWINCH support,
    ;; so we poll terminal size changes instead
    (void))

  ;; Resize polling thread (fallback for SIGWINCH)
  (define (start-resize-poller!)
    (thread
     (λ ()
       (define last-size (get-terminal-size))
       (let loop ()
         (sleep 0.25)
         (define new-size (get-terminal-size))
         (unless (equal? new-size last-size)
           (async-channel-put msg-channel
                              (resize-msg (size (car new-size) (cdr new-size))))
           (set! last-size new-size))
         (loop)))))

  ;; Main event loop
  (define (event-loop model update-fn view-fn)
    (render! model view-fn output-port)
    (let loop ([model model])
      (define msg (async-channel-get msg-channel))
      (cond
        [(quit-msg? msg) model]
        [else
         (define-values (new-model cmd) (update-fn model msg))
         (execute-cmd! cmd msg-channel)
         (render! new-model view-fn output-port)
         (loop new-model)])))

  ;; Run the program
  (parameterize ([current-program-channel msg-channel])
    (dynamic-wind
     setup!
     (λ ()
       (start-input-reader!)
       (start-resize-poller!)
       (define init-fn (program-init prog))
       (define-values (initial-model initial-cmd)
         (if (procedure? init-fn)
             (init-fn)
             (values init-fn none)))
       (execute-cmd! initial-cmd msg-channel)
       (event-loop initial-model (program-update prog) (program-view prog)))
     teardown!)))

;; ============================================================================
;; Tests
;; ============================================================================

(module+ test
  (require rackunit)

  (test-case "size struct works"
             (define s (size 80 24))
             (check-equal? (size-width s) 80)
             (check-equal? (size-height s) 24))

  (test-case "rect struct works"
             (define r (rect 0 0 80 24))
             (check-equal? (rect-x r) 0)
             (check-equal? (rect-y r) 0)
             (check-equal? (rect-width r) 80)
             (check-equal? (rect-height r) 24))

  (test-case "batch combines commands"
             (define c1 (cmd (λ (ch) 'a)))
             (define c2 (cmd (λ (ch) 'b)))
             (define batched (batch c1 none c2))
             (check-equal? (length batched) 2))

  (test-case "quit creates a cmd"
             (check-pred cmd? (quit)))

  (test-case "send-msg creates a cmd"
             (check-pred cmd? (send-msg 'hello)))

  (test-case "program struct works"
             (define p (program
                        (λ () (values 0 none))
                        (λ (model msg) (values model none))
                        (λ (model sz) "")))
             (check-pred procedure? (program-init p))
             (check-pred procedure? (program-update p))
             (check-pred procedure? (program-view p)))

  (test-case "none is recognized"
             (check-eq? none 'none)))
