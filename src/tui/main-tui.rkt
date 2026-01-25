#lang racket/base
;; Chrysalis Forge Main TUI
;; Full-screen terminal UI with complete REPL feature parity

(provide start-main-tui)

(require racket/match
         racket/string
         racket/set
         racket/format
         racket/async-channel
         racket/port
         (only-in racket/list make-list take-right first take drop)
         "../tui/program.rkt"
         "../tui/event.rkt"
         "../tui/terminal.rkt"
         "../tui/widgets/text-input.rkt"
         "../tui/text/buffer.rkt"
         "../tui/text/measure.rkt"
         "../tui/compat/legacy-style.rkt"
         "../tui/doc.rkt"
         "../tui/layout.rkt"
         "../tui/style.rkt"
         "../tui/text/ansi.rkt"
         "../tui/history.rkt"
         "../tui/widgets/palette.rkt"
         "../tui/render/screen.rkt"
         "../utils/intro-animation.rkt"
         ;; Core functionality for feature parity
         "../core/commands.rkt"
         "../core/repl.rkt"
         "../core/runtime.rkt"
         "../stores/context-store.rkt")

;; ============================================================================
;; Application State
;; ============================================================================

;; Application states
(define STATE-INTRO 'intro)
(define STATE-READY 'ready)

(struct model (state
               frame-index ; intro animation frame
               checks      ; list of (name . status) pairs
               msgs        ; List of (role . content)
               rendered-log ; List of ANSI strings (lines)
               input       ; input-model
               history     ; history-model for command history
               width       ; terminal width
               height      ; terminal height
               thinking?   ; boolean
               scroll-offset ; integer (lines from bottom)
               palette     ; palette-model
               run-turn    ; callback
               session     ; session-id
               api-key)    ; string
  #:transparent)

;; ============================================================================
;; Custom Messages
;; ============================================================================

(struct tick-msg () #:transparent)
(struct output-msg (text) #:transparent)
(struct stream-start-msg () #:transparent)
(struct stream-chunk-msg (text) #:transparent)
(struct stream-end-msg () #:transparent)
(struct command-output-msg (lines) #:transparent)

;; ============================================================================
;; Init
;; ============================================================================

;; ============================================================================
;; Styles
;; ============================================================================

(define header-style (style-set empty-style #:fg 'cyan #:bold #t))
(define subheader-style (style-set empty-style #:fg 'white #:dim #t))
(define user-style (style-set empty-style #:fg 'green))
(define assistant-style (style-set empty-style #:fg 'cyan))
(define system-style (style-set empty-style #:dim #t))
(define error-style (style-set empty-style #:fg 'red))
(define input-style (style-set empty-style #:border 'rounded #:border-fg 'cyan #:padding '(0 1)))

(define (main-tui-init #:run-turn [run-turn #f]
                       #:session-id [session-id #f]
                       #:history [history '()]
                       #:api-key [api-key #f])
  (lambda ()
    (define checks
      (list (cons "Environment" 'ok)
            (cons "API Key" (if api-key 'ok 'warn))))
    ;; Load history
    ;; Initialize history model
    (define h-model (history-init history))
    (define p-model (palette-init available-slash-commands))

    (define initial-model
      (model STATE-INTRO
             0                         ; frame-index
             checks                    ; checks
             '()                       ; msgs
             '()                       ; rendered-log
             (text-input-init #:placeholder "Type your message..."
                              #:prompt "[USER]> ")
             h-model
             80      ; width
             24      ; height
             #f      ; thinking?
             0       ; scroll-offset
             p-model
             run-turn
             session-id
             api-key))

    ;; Start tick timer for animations
    (define tick-cmd (start-ticker 100))

    (values initial-model tick-cmd)))

;; Start a periodic ticker command
(define (start-ticker interval-ms)
  (cmd (λ (ch)
         (let loop ()
           (sleep (/ interval-ms 1000.0))
           (async-channel-put ch (tick-msg))
           (loop)))))

;; ============================================================================
;; Update
;; ============================================================================

(define (main-update m evt)
  (match (model-state m)
    ['intro (update-intro m evt)]
    ['ready (update-ready m evt)]
    [_ (values m none)]))

;; Update during intro animation
(define (update-intro m evt)
  (match evt
    [(tick-msg)
     (define frame-index (model-frame-index m))
     (define checks (model-checks m))

     (cond
       ;; Still animating logo frames
       [(< frame-index (length LOGO-FRAMES))
        (values (struct-copy model m [frame-index (add1 frame-index)])
                none)]

       ;; Auto-transition to ready state after showing all frames
       ;; Auto-transition to ready state after showing all frames
       [else
        (define new-input (struct-copy text-input-model (model-input m) [focused? #t]))
        (define sys-msg (cons 'system "Welcome! Type /help for commands, or start chatting."))
        ;; Assuming width is initialized
        (define sys-lines (render-msg-to-lines sys-msg (model-width m)))

        (values (struct-copy model m
                             [state STATE-READY]
                             [input new-input]
                             [msgs (list sys-msg)]
                             [rendered-log sys-lines])
                none)])]

    ;; Handle key events during intro
    [(key-event 'esc _ _ _)
     (values m (quit))]

    [(key-event _ #\q _ _)
     (values m (quit))]

    ;; Any other key skips intro
    [(key-event _ _ _ _)
     (define new-input (struct-copy text-input-model (model-input m) [focused? #t]))
     (define sys-msg (cons 'system "Welcome! Type /help for commands, or start chatting."))
     (define sys-lines (render-msg-to-lines sys-msg (model-width m)))
     (values (struct-copy model m
                          [state STATE-READY]
                          [input new-input]
                          [msgs (list sys-msg)]
                          [rendered-log sys-lines])
             none)]

    [(resize-msg sz)
     (values (struct-copy model m
                          [width (size-width sz)]
                          [height (size-height sz)])
             none)]

    [_ (values m none)]))

;; Update in ready/chat state
;; Helper to re-render all logs (for resize)
(define (rerender-logs m)
  (define width (model-width m))
  (define new-log
    (apply append
           (for/list ([msg (in-list (model-msgs m))])
             (render-msg-to-lines msg width))))
  (struct-copy model m [rendered-log new-log]))

(define (update-ready m evt)
  ;; Check palette first
  (cond
    [(and (model-palette m) (palette-model-visible? (model-palette m)))
     (define-values (new-p cmd) (palette-update (model-palette m) evt))
     ;; Check for palette selection
     (match cmd
       [(list (list 'palette-select selected-cmd))
        ;; Execute command
        (submit-input (struct-copy model m [palette new-p]) selected-cmd)]
       [_
        (values (struct-copy model m [palette new-p]) none)])]
    [else
     ;; Normal chat update
     (match evt
       [(tick-msg) (values m none)]

       ;; Palette Toggle (Ctrl+P)
       [(key-event _ #\p (? (λ (mods) (set-member? mods 'ctrl))) _)
        (values (struct-copy model m [palette (palette-show (model-palette m))]) none)]

       ;; Scrolling (Lines) - PageUp
       [(or (key-event 'page-up _ _ _)
            (key-event _ #\u (? (λ (mods) (set-member? mods 'ctrl))) _))
        (define current (model-scroll-offset m))
        (define total (length (model-rendered-log m)))
        (define new-offset (min total (+ current 10)))
        (values (struct-copy model m [scroll-offset new-offset]) none)]

       ;; Scrolling (Lines) - PageDown
       [(or (key-event 'page-down _ _ _)
            (key-event _ #\d (? (λ (mods) (set-member? mods 'ctrl))) _))
        (define new-offset (max 0 (- (model-scroll-offset m) 10)))
        (values (struct-copy model m [scroll-offset new-offset]) none)]

       ;; Scrolling (Lines) - Shift+Up/Down
       [(key-event 'up _ (? (λ (m) (set-member? m 'shift))) _)
        (define current (model-scroll-offset m))
        (define total (length (model-rendered-log m)))
        (values (struct-copy model m [scroll-offset (min total (add1 current))]) none)]

       [(key-event 'down _ (? (λ (m) (set-member? m 'shift))) _)
        (values (struct-copy model m [scroll-offset (max 0 (sub1 (model-scroll-offset m)))]) none)]

       ;; Resize
       [(resize-msg sz)
        (define m-resized (struct-copy model m [width (size-width sz)] [height (size-height sz)]))
        (values (rerender-logs m-resized) none)]

       ;; Stream logic
       [(stream-start-msg)
        (values (struct-copy model m [thinking? #t]) none)]

       [(stream-chunk-msg text)
        (values m none)]

       [(stream-end-msg)
        (values (struct-copy model m [thinking? #f]) none)]

       [(output-msg text)
        (values (handle-assistant-response m text (model-width m)) none)]

       [(command-output-msg lines)
        (define m2
          (for/fold ([acc m]) ([line (in-list lines)])
            (append-msg acc 'system line (model-width acc))))
        (values m2 none)]

       ;; Input / History
       [_
        (match evt
          ;; History Nav
          [(key-event 'up _ _ _)
           (define-values (new-h val) (history-prev (model-history m) (text-input-value (model-input m))))
           (define new-input (struct-copy text-input-model (model-input m) [buffer (make-buffer val)]))
           (values (struct-copy model m [history new-h] [input new-input]) none)]

          [(key-event 'down _ _ _)
           (define-values (new-h val) (history-next (model-history m) (text-input-value (model-input m))))
           (define new-input (struct-copy text-input-model (model-input m) [buffer (make-buffer val)]))
           (values (struct-copy model m [history new-h] [input new-input]) none)]

          [_
           (define-values (new-input cmds) (text-input-update (model-input m) evt))
           (define new-model (struct-copy model m [input new-input]))
           ;; Check if we got a submit message
           (if (and (pair? cmds) (text-input-submit-msg? (car cmds)))
               (submit-input new-model (text-input-submit-msg-value (car cmds)))
               (values new-model none))])])]))



;; ============================================================================
;; View
;; ============================================================================

(define (main-view m sz)
  (define width (size-width sz))
  (define height (size-height sz))

  (case (model-state m)
    [(intro) (view-intro m width height)]
    [(ready) (view-ready m width height)]
    [else ""]))

;; Helper to render message to lines
(define (render-msg-to-lines msg width)
  (define d (render-message msg width))
  (render-doc-to-lines d width))

(define (render-doc-to-lines doc width)
  (define h (measure-doc-height doc width))
  (if (= h 0)
      '()
      (let ([scr (make-screen width h)])
        (screen-write-doc! scr doc)
        (screen-lines scr))))

(define (render-document doc width height)
  (define scr (make-screen width height))
  (screen-write-doc! scr doc)
  (string-join (screen-lines scr) "\r\n"))


;; Helper to append message to log
(define (append-msg m role content width)
  (define msg (cons role content))
  (define new-lines (render-msg-to-lines msg width))
  (define current-scroll (model-scroll-offset m))
  ;; Auto-scroll: if near bottom (<= 3 lines), snap to bottom (0).
  ;; Else maintain relative position.
  (define new-scroll
    (if (<= current-scroll 3)
        0
        (+ current-scroll (length new-lines))))
  (struct-copy model m
               [msgs (append (model-msgs m) (list msg))]
               [rendered-log (append (model-rendered-log m) new-lines)]
               [scroll-offset new-scroll]))

(define (handle-assistant-response m response width)
  (define m-with-msg (append-msg m 'assistant response width))
  (struct-copy model m-with-msg [thinking? #f]))

(define (submit-input m input)
  (define width (model-width m))
  (define trimmed (string-trim input))
  (cond
    [(string=? trimmed "") (values m none)]

    ;; Handle /exit
    [(or (equal? trimmed "/exit") (equal? trimmed "/quit"))
     (values m (quit))]

    ;; Handle slash commands
    [(string-prefix? trimmed "/")
     (define cmd-name (first (string-split (substring trimmed 1))))
     (define output-str
       (with-output-to-string
         (λ ()
           (with-handlers ([exn:fail? (λ (e) (printf "[ERROR] ~a" (exn-message e)))])
             (handle-slash-command cmd-name trimmed #:run-turn (model-run-turn m))))))

     (define m1 (append-msg m 'user trimmed width))
     (define sys-msgs (if (string=? output-str "") '() (string-split output-str "\n")))

     (define m2
       (for/fold ([acc m1]) ([line (in-list sys-msgs)])
         (append-msg acc 'system line width)))

     (define new-input (struct-copy text-input-model (model-input m) [buffer (make-buffer "")]))
     (define new-h (history-append (model-history m) trimmed))
     (values (struct-copy model m2 [input new-input] [history new-h]) none)]

    ;; Regular message - send to LLM
    [else
     (define m1 (append-msg m 'user trimmed width))
     (define new-input (struct-copy text-input-model (model-input m) [buffer (make-buffer "")]))
     (define new-h (history-append (model-history m) trimmed))

     (define turn-cmd
       (if (model-run-turn m)
           (cmd (λ (ch)
                  ((model-run-turn m) (model-session m) trimmed
                                      (lambda (type data)
                                        (match type
                                          ['content (async-channel-put ch (output-msg data))]
                                          ['stream-start (async-channel-put ch (stream-start-msg))]
                                          ['stream-chunk (async-channel-put ch (stream-chunk-msg data))]
                                          ['stream-end (async-channel-put ch (stream-end-msg))]
                                          ['error (async-channel-put ch (output-msg (format "[ERROR] ~a" data)))]
                                          [_ (void)])))))
           none))

     (values (struct-copy model m1 [input new-input] [history new-h] [thinking? #t]) turn-cmd)]))

(define (view-intro m width height)
  (define output-lines '())

  (define frame-index (min (model-frame-index m) (sub1 (length LOGO-FRAMES))))
  (define current-frame (list-ref LOGO-FRAMES frame-index))

  ;; Center the frame
  (define frame-lines (string-split current-frame "\n"))
  (define frame-height (length frame-lines))
  (define max-line-width (apply max 1 (map text-width frame-lines)))
  (define top-padding (max 0 (quotient (- height frame-height) 2)))
  (define left-padding (max 0 (quotient (- width max-line-width) 2)))
  (for ([line (in-list frame-lines)])
    (define styled-line (gradient line 'cyan 'magenta))
    (define padded (string-append (make-string left-padding #\space) styled-line))
    (set! output-lines (append output-lines (list padded))))

  ;; Title (if animation near complete)
  (when (>= frame-index (sub1 (length LOGO-FRAMES)))
    (set! output-lines (append output-lines (list "" "")))
    (define title (gradient "CHRYSALIS FORGE" 'cyan 'magenta))
    (set! output-lines (append output-lines (list (center-text title width)))))

  ;; System checks
  (when (>= frame-index (sub1 (length LOGO-FRAMES)))
    (set! output-lines (append output-lines (list "")))
    (for ([check (in-list (model-checks m))])
      (define name (car check))
      (define status (cdr check))
      (define icon (hash-ref STATUS-ICONS status "?"))
      (define col (case status
                    [(ok) 'green]
                    [(warn) 'yellow]
                    [(fail) 'red]
                    [else 'cyan]))
      (define line (string-append "    " (color col icon) " " name))
      (set! output-lines (append output-lines (list (center-text line width))))))

  ;; Help text
  (set! output-lines (append output-lines (list "" "")))
  (set! output-lines (append output-lines
                             (list (center-text (dim "Press any key to continue...") width))))

  ;; Pad to fill screen height
  (define remaining (max 0 (- height (length output-lines))))
  (set! output-lines (append output-lines (make-list remaining "")))

  (string-join output-lines "\r\n"))

;; Ready/chat screen view
(define (view-ready m width height)
  ;; Header
  (define header
    (hjoin (list (txt "CHRYSALIS FORGE" header-style)
                 (txt " | Ready" subheader-style))
           #:sep ""))
  (define divider (txt (make-string width #\─) subheader-style))

  (define header-h 2)
  (define input-h 3)
  (define status-h 1)
  (define msg-h (max 0 (- height header-h input-h status-h)))

  ;; Render messages from rendered-log
  ;; model-scroll-offset is lines from bottom
  (define log-lines (model-rendered-log m))
  (define total-lines (length log-lines))
  (define scroll (model-scroll-offset m))

  ;; Slice lines
  ;; We want to show lines [end - scroll - msg-h, end - scroll]
  (define end-idx (max 0 (- total-lines scroll)))
  (define start-idx (max 0 (- end-idx msg-h)))

  (define visible-lines
    (if (and (> end-idx 0) (< start-idx end-idx))
        (take (drop log-lines start-idx) (- end-idx start-idx))
        '()))

  ;; Convert lines to docs
  (define msg-docs
    (for/list ([line (in-list visible-lines)])
      (ansi-string->doc line)))

  (define msg-col (vjoin msg-docs))

  (define input-view (box (text-input-view (model-input m) (- width 2)) (style-set input-style #:width width)))
  (define status (txt (format "/help | PgUp/Dn Scroll 10 | Ctrl+Up/Dn 1 | Ctrl+P Palette | Session: ~a" (or (model-session m) "N/A")) subheader-style))

  (define root
    (vjoin (list header divider
                 (box msg-col (style-set empty-style #:height msg-h #:max-height msg-h #:valign 'bottom))
                 input-view status)))

  ;; Overlay Palette if visible
  (cond
    [(and (model-palette m) (palette-model-visible? (model-palette m)))
     (doc-overlay (list root (palette-view (model-palette m) width)))]
    [else (render-document root width height)]))

(define (render-message msg width)
  (match-define (cons role content) msg)
  (match role
    ['user
     (hjoin (list (txt "[USER]> " user-style)
                  (box (txt content) (style-set empty-style #:wrap? #t #:width (- width 8))))
            #:sep "")]
    ['assistant
     (hjoin (list (txt "[AI] " assistant-style)
                  (box (txt content) (style-set empty-style #:wrap? #t #:width (- width 6))))
            #:sep "")]
    ['system
     (box (txt content system-style) (style-set empty-style #:wrap? #t #:width width))]
    [_
     (box (txt content) (style-set empty-style #:wrap? #t #:width width))]))

;; Helper to center text
(define (center-text text width)
  (define text-len (text-width text))
  (define padding (max 0 (quotient (- width text-len) 2)))
  (string-append (make-string padding #\space) text))

(define (measure-doc-height doc width)
  (define l (layout doc width 10000))
  (inexact->exact (ceiling (rect-height (layout-node-rect l)))))

;; ============================================================================
;; Entry Point
;; ============================================================================

(define (start-main-tui #:run-turn [run-turn #f]
                        #:session-id [session-id #f]
                        #:api-key [api-key #f])
  ;; Suppress the return value so it doesn't print the model
  (void
   (run-program
    (program (main-tui-init #:run-turn run-turn
                            #:session-id session-id
                            #:api-key api-key)
             main-update
             main-view)
    #:alt-screen? #t
    #:mouse? #f
    #:bracketed-paste? #t)))

;; ============================================================================
;; Tests
;; ============================================================================

(module+ test
  (require rackunit)

  (test-case "model struct creation"
             (define m (model STATE-INTRO        ; state
                              0                   ; frame-index
                              '()                 ; checks
                              '()                 ; msgs
                              '()                 ; rendered-log
                              (text-input-init)   ; input
                              (history-init '())  ; history
                              80                  ; width
                              24                  ; height
                              #f                  ; thinking?
                              0                   ; scroll-offset
                              #f                  ; palette
                              #f                  ; run-turn
                              #f                  ; session
                              #f))                ; api-key
             (check-eq? (model-state m) STATE-INTRO))

  (test-case "center-text works"
             (define result (center-text "hello" 20))
             (check-equal? (string-length result) 12))

  (test-case "auto-scroll logic"
    ;; Create a dummy model for testing
    (define base-m 
      (model 'ready 0 '() '() '() 
             (text-input-init) (history-init) 80 24 #f 
             0 #f #f #f #f))
    
    ;; Case 1: At bottom (offset 0) -> Should stay at bottom (offset 0)
    (define m1 (append-msg base-m 'user "New message" 80))
    (check-equal? (model-scroll-offset m1) 0 "Should snap to bottom when already at bottom")

    ;; Case 2: Near bottom (offset 2) -> Should snap to bottom (offset 0)
    (define m2 (struct-copy model base-m [scroll-offset 2]))
    (define m3 (append-msg m2 'user "New message" 80))
    (check-equal? (model-scroll-offset m3) 0 "Should snap to bottom when near bottom")

    ;; Case 3: Far up (offset 10) -> Should maintain relative position
    ;; We need to know how many lines "New message" takes. 
    ;; With width 80, "New message" is 1 line.
    ;; But append-msg calls render-msg-to-lines which wraps it in boxes/styling.
    ;; Let's inspect the actual lines added to check the offset increase.
    (define m4 (struct-copy model base-m [scroll-offset 10]))
    (define m5 (append-msg m4 'user "New message" 80))
    (define added-lines (- (length (model-rendered-log m5)) (length (model-rendered-log m4))))
    (check-equal? (model-scroll-offset m5) (+ 10 added-lines) "Should maintain relative position when scrolled up"))

  )

;; Direct run support
(module+ main
  (start-main-tui))
