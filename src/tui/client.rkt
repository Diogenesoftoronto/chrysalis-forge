#lang racket/base
;; Chrysalis Forge TUI Client
;; Full-screen terminal UI using Bubble Tea-style Elm architecture

(provide start-tui-client)

(require racket/match
         racket/string
         racket/set
         (only-in racket/list make-list take-right)
         racket/async-channel
         racket/format
         "../tui/tui.rkt"
         "../service/client.rkt"
         "../utils/intro-animation.rkt"
         "../tui/compat/legacy-style.rkt")

;; ============================================================================
;; Application State
;; ============================================================================

;; Application view states
(define STATE-INTRO    'intro)
(define STATE-AUTH     'auth)
(define STATE-CHAT     'chat)

;; Auth modes
(define AUTH-LOGIN    'login)
(define AUTH-REGISTER 'register)
(define AUTH-CHOICE   'choice)

;; Model for the entire TUI application
(struct model
  (state                 ; current state: intro, auth, chat
   frame-index           ; current intro animation frame
   frame-tick            ; tick counter for animation timing
   check-index           ; current system check index
   checks                ; list of (name . status) for system checks
   auth-mode             ; login, register, or choice
   auth-field            ; current auth field: 'email 'password 'display-name
   email-input           ; text-input model for email
   password-input        ; text-input model for password
   display-name-input    ; text-input model for display name
   messages              ; list of chat messages (role . content)
   current-input         ; text-input model for chat input
   viewport              ; viewport model for chat history
   service-client        ; ServiceClient or #f
   service-url           ; URL to connect to
   api-key               ; Optional API key
   error-message         ; Current error message or #f
   streaming-text        ; Accumulated streaming response or #f
   streaming-index       ; Current index for streaming animation
   )
  #:transparent)

;; ============================================================================
;; Custom Messages
;; ============================================================================

(struct tick-msg () #:transparent)
(struct service-connected-msg (client) #:transparent)
(struct service-error-msg (error) #:transparent)
(struct auth-success-msg () #:transparent)
(struct auth-error-msg (message) #:transparent)
(struct session-created-msg (session-id) #:transparent)
(struct chat-response-msg (content) #:transparent)

;; ============================================================================
;; Init
;; ============================================================================

(define (client-init url api-key)
  (lambda ()
    (define checks
      (list (cons "Configuration" 'pending)
            (cons "Connection" 'pending)
            (cons "Authentication" 'pending)))

    (define initial-model
      (model STATE-INTRO
             0                         ; frame-index
             0                         ; frame-tick
             0                         ; check-index
             checks                    ; checks
             AUTH-CHOICE               ; auth-mode
             'email                    ; auth-field
             (text-input-init #:placeholder "user@example.com"
                              #:prompt "Email: "
                              #:validation validate-email)
             (text-input-init #:placeholder "********"
                              #:prompt "Password: "
                              #:mask-char #\*)
             (text-input-init #:placeholder "Your Name"
                              #:prompt "Display Name: ")
             '()                       ; messages
             (text-input-init #:placeholder "Type your message..."
                              #:prompt ">>> ")
             (viewport-init #:width 80 #:height 20 #:show-indicators? #t)
             #f                        ; service-client
             url                       ; service-url
             api-key                   ; api-key
             #f                        ; error-message
             #f                        ; streaming-text
             0                         ; streaming-index
             ))

    ;; Start tick timer for animations
    (define tick-cmd (start-ticker 150))

    ;; Start connecting to service
    (define connect-cmd (connect-service-cmd url api-key))

    (values initial-model (batch tick-cmd connect-cmd))))

;; Start a periodic ticker command
(define (start-ticker interval-ms)
  (cmd (λ (ch)
         (let loop ()
           (sleep (/ interval-ms 1000.0))
           (async-channel-put ch (tick-msg))
           (loop)))))

;; Connect to service asynchronously
(define (connect-service-cmd url api-key)
  (cmd (λ (ch)
         (with-handlers ([exn:fail?
                          (λ (e) (async-channel-put ch (service-error-msg (exn-message e))))])
           (define client (connect-service! url #:api-key api-key))
           (if client
               (async-channel-put ch (service-connected-msg client))
               (async-channel-put ch (service-error-msg "Failed to connect")))))))

;; Login asynchronously
(define (login-cmd email password)
  (cmd (λ (ch)
         (with-handlers ([exn:fail?
                          (λ (e) (async-channel-put ch (auth-error-msg (exn-message e))))])
           (if (client-login! email password)
               (async-channel-put ch (auth-success-msg))
               (async-channel-put ch (auth-error-msg "Login failed")))))))

;; Register asynchronously
(define (register-cmd email password display-name)
  (cmd (λ (ch)
         (with-handlers ([exn:fail?
                          (λ (e) (async-channel-put ch (auth-error-msg (exn-message e))))])
           (if (client-register! email password #:display-name display-name)
               (async-channel-put ch (auth-success-msg))
               (async-channel-put ch (auth-error-msg "Registration failed")))))))

;; Create session asynchronously
(define (create-session-cmd)
  (cmd (λ (ch)
         (define session-id (client-create-session! #:mode "code"))
         (when session-id
           (async-channel-put ch (session-created-msg session-id))))))

;; Send chat message asynchronously
(define (chat-cmd message)
  (cmd (λ (ch)
         (with-handlers ([exn:fail?
                          (λ (e) (async-channel-put ch (chat-response-msg (format "Error: ~a" (exn-message e)))))])
           (define response (client-chat message))
           (when response
             (async-channel-put ch (chat-response-msg response)))))))

;; ============================================================================
;; Update
;; ============================================================================

(define (client-update m evt)
  (match (model-state m)
    ['intro (update-intro m evt)]
    ['auth (update-auth m evt)]
    ['chat (update-chat m evt)]
    [_ (values m none)]))

;; Update during intro animation
(define (update-intro m evt)
  (match evt
    [(tick-msg)
     (define frame-tick (model-frame-tick m))
     (define frame-index (model-frame-index m))
     (define checks (model-checks m))
     (define check-index (model-check-index m))

     ;; Advance animation
     (cond
       ;; Still animating logo frames
       [(< frame-index (length LOGO-FRAMES))
        (if (>= frame-tick 2)  ; Every 2 ticks advance frame
            (values (struct-copy model m
                                 [frame-index (add1 frame-index)]
                                 [frame-tick 0])
                    none)
            (values (struct-copy model m [frame-tick (add1 frame-tick)])
                    none))]

       ;; Animating system checks
       [(< check-index (length checks))
        (define updated-checks
          (for/list ([c (in-list checks)]
                     [i (in-naturals)])
            (if (= i check-index)
                (cons (car c) (if (model-service-client m) 'ok 'pending))
                c)))
        (values (struct-copy model m
                             [checks updated-checks]
                             [check-index (add1 check-index)])
                none)]

       ;; Intro complete - transition to auth or chat
       [else
        (if (and (model-service-client m) (model-api-key m))
            ;; Already authenticated, go to chat
            (values (struct-copy model m [state STATE-CHAT])
                    (create-session-cmd))
            ;; Need to authenticate
            (values (struct-copy model m [state STATE-AUTH])
                    none))])]

    ;; Service connected
    [(service-connected-msg client)
     (values (struct-copy model m [service-client client])
             none)]

    ;; Service error
    [(service-error-msg error)
     (define updated-checks
       (for/list ([c (model-checks m)]
                  [i (in-naturals)])
         (if (= i 1) ; Connection check
             (cons (car c) 'fail)
             c)))
     (values (struct-copy model m
                          [checks updated-checks]
                          [error-message error])
             none)]

    ;; Quit on Ctrl+C or q
    [(key-event 'esc _ _ _)
     (values m (quit))]
    [(key-event _ #\q (? (λ (mods) (set-member? mods 'ctrl))) _)
     (values m (quit))]

    [_ (values m none)]))

;; Update during auth screen
(define (update-auth m evt)
  (match evt
    [(tick-msg) (values m none)]

    ;; Auth mode selection
    [(key-event _ #\l _ _)
     #:when (eq? (model-auth-mode m) AUTH-CHOICE)
     (define new-email (struct-copy text-input-model (model-email-input m) [focused? #t]))
     (values (struct-copy model m
                          [auth-mode AUTH-LOGIN]
                          [auth-field 'email]
                          [email-input new-email])
             none)]

    [(key-event _ #\r _ _)
     #:when (eq? (model-auth-mode m) AUTH-CHOICE)
     (define new-email (struct-copy text-input-model (model-email-input m) [focused? #t]))
     (values (struct-copy model m
                          [auth-mode AUTH-REGISTER]
                          [auth-field 'email]
                          [email-input new-email])
             none)]

    ;; Tab to switch fields
    [(key-event 'tab _ _ _)
     #:when (not (eq? (model-auth-mode m) AUTH-CHOICE))
     (define field (model-auth-field m))
     (define next-field
       (case field
         [(email) 'password]
         [(password) (if (eq? (model-auth-mode m) AUTH-REGISTER) 'display-name 'email)]
         [(display-name) 'email]
         [else 'email]))
     (values (focus-auth-field m next-field) none)]

    ;; Enter to submit
    [(key-event 'enter _ _ _)
     #:when (not (eq? (model-auth-mode m) AUTH-CHOICE))
     (define email (text-input-value (model-email-input m)))
     (define password (text-input-value (model-password-input m)))
     (if (eq? (model-auth-mode m) AUTH-LOGIN)
         (values m (login-cmd email password))
         (let ([display-name (text-input-value (model-display-name-input m))])
           (values m (register-cmd email password display-name))))]

    ;; Auth success
    [(auth-success-msg)
     (values (struct-copy model m [state STATE-CHAT])
             (create-session-cmd))]

    ;; Auth error
    [(auth-error-msg message)
     (values (struct-copy model m [error-message message])
             none)]

    ;; Escape to go back
    [(key-event 'esc _ _ _)
     (if (eq? (model-auth-mode m) AUTH-CHOICE)
         (values m (quit))
         (values (struct-copy model m [auth-mode AUTH-CHOICE]) none))]

    ;; Pass key events to focused input
    [_
     (define field (model-auth-field m))
     (case field
       [(email)
        (define-values (new-input cmds) (text-input-update (model-email-input m) evt))
        (values (struct-copy model m [email-input new-input]) none)]
       [(password)
        (define-values (new-input cmds) (text-input-update (model-password-input m) evt))
        (values (struct-copy model m [password-input new-input]) none)]
       [(display-name)
        (define-values (new-input cmds) (text-input-update (model-display-name-input m) evt))
        (values (struct-copy model m [display-name-input new-input]) none)]
       [else (values m none)])]))

(define (focus-auth-field m field)
  (define email (struct-copy text-input-model (model-email-input m)
                             [focused? (eq? field 'email)]))
  (define password (struct-copy text-input-model (model-password-input m)
                                [focused? (eq? field 'password)]))
  (define display-name (struct-copy text-input-model (model-display-name-input m)
                                    [focused? (eq? field 'display-name)]))
  (struct-copy model m
               [auth-field field]
               [email-input email]
               [password-input password]
               [display-name-input display-name]))

;; Update during chat
(define (update-chat m evt)
  (match evt
    [(tick-msg)
     ;; Animate streaming text
     (if (model-streaming-text m)
         (let* ([full-text (model-streaming-text m)]
                [idx (model-streaming-index m)]
                [new-idx (min (string-length full-text) (+ idx 3))])
           (if (>= new-idx (string-length full-text))
               ;; Streaming complete
               (let ([new-messages (append (model-messages m)
                                           (list (cons 'assistant full-text)))])
                 (values (struct-copy model m
                                      [messages new-messages]
                                      [streaming-text #f]
                                      [streaming-index 0]
                                      [viewport (update-viewport-content m new-messages)])
                         none))
               ;; Continue streaming
               (values (struct-copy model m [streaming-index new-idx])
                       none)))
         (values m none))]

    ;; Chat response received
    [(chat-response-msg content)
     (values (struct-copy model m
                          [streaming-text content]
                          [streaming-index 0])
             none)]

    ;; Session created
    [(session-created-msg session-id)
     (values m none)]

    ;; Enter to send message
    [(text-input-submit-msg value)
     (define new-messages (append (model-messages m)
                                  (list (cons 'user value))))
     (define new-input
       (struct-copy text-input-model (model-current-input m)
                    [buffer (make-buffer "")]))
     (values (struct-copy model m
                          [messages new-messages]
                          [current-input new-input]
                          [viewport (update-viewport-content m new-messages)])
             (chat-cmd value))]

    ;; Escape to quit
    [(key-event 'esc _ _ _)
     (values m (quit))]

    ;; Ctrl+C to quit
    [(key-event _ #\c (? (λ (mods) (set-member? mods 'ctrl))) _)
     (values m (quit))]

    ;; Page up/down for viewport
    [(key-event 'page-up _ _ _)
     (define-values (new-viewport _) (viewport-update (model-viewport m) evt))
     (values (struct-copy model m [viewport new-viewport]) none)]

    [(key-event 'page-down _ _ _)
     (define-values (new-viewport _) (viewport-update (model-viewport m) evt))
     (values (struct-copy model m [viewport new-viewport]) none)]

    ;; Default: pass to text input
    [_
     (define-values (new-input cmds) (text-input-update (model-current-input m) evt))
     (define new-model (struct-copy model m [current-input new-input]))
     ;; Check for submit messages
     (if (and (pair? cmds) (text-input-submit-msg? (car cmds)))
         (client-update new-model (car cmds))
         (values new-model none))]))

(define (update-viewport-content m messages)
  (define content (format-messages messages))
  (viewport-set-content (model-viewport m) content))

(define (format-messages messages)
  (string-join
   (for/list ([msg (in-list messages)])
     (define role (car msg))
     (define content (cdr msg))
     (if (eq? role 'user)
         (format "You: ~a" content)
         (format "Agent: ~a" content)))
   "\n\n"))

;; ============================================================================
;; View
;; ============================================================================

(define (client-view m sz)
  (case (model-state m)
    [(intro) (view-intro m sz)]
    [(auth) (view-auth m sz)]
    [(chat) (view-chat m sz)]
    [else ""]))

;; Intro screen view
(define (view-intro m sz)
  (define width (size-width sz))
  (define height (size-height sz))
  (define frame-index (min (model-frame-index m) (sub1 (length LOGO-FRAMES))))
  (define current-frame (list-ref LOGO-FRAMES frame-index))

  ;; Center the frame - use text-width for Unicode chars
  (define frame-lines (string-split current-frame "\n"))
  (define frame-height (length frame-lines))
  (define max-line-width (apply max 0 (map text-width frame-lines)))

  ;; Build output lines
  (define output-lines '())

  ;; Top padding
  (define top-padding (max 0 (quotient (- height frame-height 12) 2)))
  (set! output-lines (append output-lines (make-list top-padding "")))

  ;; Logo frame (centered)
  (define left-padding (max 0 (quotient (- width max-line-width) 2)))
  (for ([line (in-list frame-lines)])
    (define styled-line (gradient line 'cyan 'magenta))
    (define padded (string-append (make-string left-padding #\space) styled-line))
    (set! output-lines (append output-lines (list padded))))

  ;; Title (if animation complete)
  (when (>= frame-index (sub1 (length LOGO-FRAMES)))
    (set! output-lines (append output-lines (list "" "")))
    (define title (gradient "CHRYSALIS FORGE" 'cyan 'magenta))
    (set! output-lines (append output-lines (list (center-text title width)))))

  ;; System checks
  (set! output-lines (append output-lines (list "" "")))
  (for ([check (in-list (model-checks m))])
    (define name (car check))
    (define status (cdr check))
    (define icon (hash-ref STATUS-ICONS status "?"))
    (define col (case status
                  [(ok) 'green]
                  [(fail) 'red]
                  [(pending) 'cyan]
                  [else 'white]))
    (define check-line (string-append (color col icon) " " name))
    (set! output-lines (append output-lines (list (center-text check-line width)))))

  ;; Help text
  (set! output-lines (append output-lines (list "" "")))
  (set! output-lines (append output-lines
                             (list (center-text (dim "ESC to quit | Connecting...") width))))

  ;; Pad to fill screen height
  (define remaining (max 0 (- height (length output-lines))))
  (set! output-lines (append output-lines (make-list remaining "")))

  ;; Join all lines with CR+LF for raw terminal mode
  (string-join output-lines "\r\n"))

;; Auth screen view
(define (view-auth m sz)
  (define width (size-width sz))
  (define height (size-height sz))
  (define output-lines '())

  (define title (bold (gradient "CHRYSALIS FORGE" 'cyan 'magenta)))

  ;; Calculate content lines based on auth mode
  (define content-lines
    (case (model-auth-mode m)
      [(choice)
       (list
        (center-text title width)
        ""
        ""
        (center-text "Authentication Required" width)
        ""
        (center-text (string-append "[" (bold "l") "] Login") width)
        (center-text (string-append "[" (bold "r") "] Register") width)
        ""
        (center-text (dim "Press ESC to quit") width))]

      [(login)
       (list
        (center-text title width)
        ""
        ""
        (center-text (bold "Login") width)
        ""
        (center-text (text-input-view (model-email-input m) 40) width)
        (center-text (text-input-view (model-password-input m) 40) width)
        ""
        (center-text (dim "Tab: switch fields | Enter: submit | ESC: back") width))]

      [(register)
       (list
        (center-text title width)
        ""
        ""
        (center-text (bold "Register") width)
        ""
        (center-text (text-input-view (model-email-input m) 40) width)
        (center-text (text-input-view (model-password-input m) 40) width)
        (center-text (text-input-view (model-display-name-input m) 40) width)
        ""
        (center-text (dim "Tab: switch fields | Enter: submit | ESC: back") width))]

      [else '()]))

  ;; Add error message if present
  (define with-error
    (if (model-error-message m)
        (append content-lines
                (list "" (center-text (color 'red (model-error-message m)) width)))
        content-lines))

  ;; Vertical centering
  (define content-height (length with-error))
  (define top-pad (max 0 (quotient (- height content-height) 3)))

  ;; Build final output
  (set! output-lines (make-list top-pad ""))
  (set! output-lines (append output-lines with-error))

  ;; Pad to fill screen height
  (define remaining (max 0 (- height (length output-lines))))
  (set! output-lines (append output-lines (make-list remaining "")))

  ;; Join with CR+LF for raw terminal mode
  (string-join output-lines "\r\n"))

;; Chat screen view
(define (view-chat m sz)
  (define width (size-width sz))
  (define height (size-height sz))
  (define output-lines '())

  ;; Header
  (define header-text (string-append (bold (color 'cyan "CHRYSALIS FORGE")) " " (dim "| Connected")))
  (define header-line (make-string width #\─))
  (set! output-lines (list header-text header-line))

  ;; Calculate available height for messages
  (define header-height 2)
  (define input-height 2)
  (define status-height 2)
  (define viewport-height (max 3 (- height header-height input-height status-height)))

  ;; Messages content with streaming
  (define messages-content
    (let ([base (format-messages (model-messages m))])
      (if (model-streaming-text m)
          (let* ([full (model-streaming-text m)]
                 [idx (model-streaming-index m)]
                 [partial (substring full 0 idx)])
            (string-append base
                           (if (string=? base "") "" "\n\n")
                           "Agent: " partial "▌"))
          base)))

  ;; Split messages into lines and take last viewport-height lines
  (define all-message-lines (if (string=? messages-content "")
                                '()
                                (string-split messages-content "\n")))
  (define visible-lines
    (if (> (length all-message-lines) viewport-height)
        (take-right all-message-lines viewport-height)
        all-message-lines))

  ;; Pad message area to viewport-height
  (define padded-messages
    (if (< (length visible-lines) viewport-height)
        (append visible-lines (make-list (- viewport-height (length visible-lines)) ""))
        visible-lines))

  (set! output-lines (append output-lines padded-messages))

  ;; Input area
  (set! output-lines (append output-lines (list (make-string width #\─))))
  (define input-view (text-input-view
                      (struct-copy text-input-model (model-current-input m) [focused? #t])
                      width))
  (set! output-lines (append output-lines (list input-view)))

  ;; Status bar
  (set! output-lines (append output-lines
                             (list (make-string width #\─)
                                   (dim (format "~a messages | ESC to quit" (length (model-messages m)))))))

  ;; Pad to fill screen height
  (define remaining (max 0 (- height (length output-lines))))
  (set! output-lines (append output-lines (make-list remaining "")))

  ;; Join with CR+LF for raw terminal mode
  (string-join output-lines "\r\n"))

;; Helper to convert doc to string
(define (doc->string d width)
  (match d
    [(doc-text content _) content]
    [(doc-block child _) (doc->string child width)]
    [(doc-row children _) (string-join (map (λ (c) (doc->string c width)) children) "")]
    [(doc-col children _) (string-join (map (λ (c) (doc->string c width)) children) "\n")]
    [(doc-spacer w h _) (make-string (or w 0) #\space)]
    [(doc-overlay children) (if (null? children) "" (doc->string (car children) width))]
    [(doc-empty) ""]
    [(? string?) d]
    [_ ""]))

;; Helper to center text (uses text-width to handle ANSI codes)
(define (center-text text width)
  (define text-len (text-width text))
  (define padding (max 0 (quotient (- width text-len) 2)))
  (string-append (make-string padding #\space) text))

;; ============================================================================
;; Entry Point
;; ============================================================================

(define (start-tui-client url #:api-key [api-key #f])
  (run-program
   (program (client-init url api-key)
            client-update
            client-view)
   #:alt-screen? #t
   #:mouse? #f
   #:bracketed-paste? #t))

;; ============================================================================
;; Tests
;; ============================================================================

(module+ test
  (require rackunit)

  (test-case "model struct creation"
             (define m (model STATE-INTRO 0 0 0 '() AUTH-CHOICE 'email
                              (text-input-init) (text-input-init) (text-input-init)
                              '() (text-input-init) (viewport-init)
                              #f "http://localhost:8080" #f #f #f 0))
             (check-eq? (model-state m) STATE-INTRO))

  (test-case "center-text works"
             (define result (center-text "hello" 20))
             (check-equal? (string-length result) 12))  ; 7 spaces + 5 chars

  (test-case "format-messages handles empty"
             (check-equal? (format-messages '()) ""))

  (test-case "format-messages formats correctly"
             (define msgs (list (cons 'user "hi") (cons 'assistant "hello")))
             (define result (format-messages msgs))
             (check-true (string-contains? result "You: hi"))
             (check-true (string-contains? result "Agent: hello"))))
