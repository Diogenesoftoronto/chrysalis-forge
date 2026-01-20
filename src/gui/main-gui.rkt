#lang racket/gui

(require racket/class racket/string racket/format racket/list racket/file racket/date json racket/system
         "../stores/context-store.rkt"
         "../llm/dspy-core.rkt"
         "../utils/dotenv.rkt"
         "../llm/model-registry.rkt"
         "../llm/pricing-model.rkt"
         "../core/workflow-engine.rkt"
         "theme-system.rkt"
         "chat-widget.rkt"
         "widget-framework.rkt"
         "notification-system.rkt"
         "animation-engine.rkt")

(provide run-gui!)

;; ============================================================================
;; Parameters & State
;; ============================================================================

(define current-model (make-parameter (or (getenv "MODEL") "gpt-5.2")))
(define current-mode (make-parameter 'code))
(define session-cost (box 0.0))
(define session-tokens (box 0))
(define first-message-sent? (box #f)) ; Track if first message sent for title generation

;; GUI-specific config parameters (mirror main.rkt)
(define gui-base-url (make-parameter (or (getenv "OPENAI_API_BASE") "https://api.openai.com/v1")))
(define gui-vision-model (make-parameter (or (getenv "VISION_MODEL") (current-model))))
(define gui-judge-model (make-parameter (or (getenv "LLM_JUDGE_MODEL") (current-model))))
(define gui-budget (make-parameter (or (and (getenv "BUDGET") (string->number (getenv "BUDGET"))) +inf.0)))
(define gui-timeout (make-parameter (or (and (getenv "TIMEOUT") (string->number (getenv "TIMEOUT"))) +inf.0)))
(define gui-priority (make-parameter (or (getenv "PRIORITY") "best")))
(define gui-security-level (make-parameter (or (and (getenv "PERMS") (string->number (getenv "PERMS"))) 1)))
(define gui-llm-judge (make-parameter (or (and (getenv "LLM_JUDGE") (not (equal? (getenv "LLM_JUDGE") "0"))) #f)))
(define gui-debug-level (make-parameter (or (and (getenv "DEBUG") (string->number (getenv "DEBUG"))) 0)))
(define gui-pretty (make-parameter (or (getenv "PRETTY") "none")))

;; ============================================================================
;; Theme Colors (now via theme-system.rkt)
;; ============================================================================

(define (bg-color) (theme-ref 'bg))
(define (fg-color) (theme-ref 'fg))
(define (accent-color) (theme-ref 'accent))
(define (user-msg-bg) (theme-ref 'user-msg-bg))
(define (assistant-msg-bg) (theme-ref 'assistant-msg-bg))
(define (input-bg) (theme-ref 'input-bg))
(define (button-bg) (theme-ref 'button-bg))

;; ============================================================================
;; Main Frame
;; ============================================================================

(define main-frame
  (new frame%
       [label "Chrysalis Forge"]
       [width 900]
       [height 700]
       [style '(fullscreen-button)]))

;; ============================================================================
;; Notification Manager & Animation Engine
;; ============================================================================

(define notif-manager (make-notification-manager main-frame))
(define anim-manager (make-animation-manager))

;; Refresh theme colors across the UI
(define (refresh-theme-colors!)
  (apply-theme! main-frame)
  (send main-frame refresh))

;; ============================================================================
;; Menu Bar
;; ============================================================================

(define menu-bar (new menu-bar% [parent main-frame]))

(define file-menu (new menu% [label "&File"] [parent menu-bar]))
(void (new menu-item%
           [label "New Session"]
           [parent file-menu]
           [callback (λ (item event) (new-session-dialog))]))
(void (new menu-item%
           [label "Switch Session"]
           [parent file-menu]
           [callback (λ (item event) (switch-session-dialog))]))
(void (new separator-menu-item% [parent file-menu]))
(void (new menu-item%
           [label "E&xit"]
           [parent file-menu]
           [callback (λ (item event) (send main-frame on-close) (send main-frame show #f))]))

(define edit-menu (new menu% [label "&Edit"] [parent menu-bar]))
(void (new menu-item%
           [label "Clear Chat"]
           [parent edit-menu]
           [callback (λ (item event) (clear-chat!))]))

(define tools-menu (new menu% [label "&Tools"] [parent menu-bar]))
(void (new menu-item%
           [label "Configuration..."]
           [parent tools-menu]
           [callback (λ (item event) (show-config-dialog))]))
(void (new menu-item%
           [label "Workflows..."]
           [parent tools-menu]
           [callback (λ (item event) (show-workflows-dialog))]))
(void (new menu-item%
           [label "Run Raco Command..."]
           [parent tools-menu]
           [callback (λ (item event) (show-raco-dialog))]))
(void (new separator-menu-item% [parent tools-menu]))
(void (new menu-item%
           [label "Initialize Project"]
           [parent tools-menu]
           [callback (λ (item event) (init-project!))]))
(void (new separator-menu-item% [parent tools-menu]))

;; Theme submenu
(define theme-menu (new menu% [label "Theme"] [parent tools-menu]))
(for ([theme-name (in-list (list-themes))])
  (new menu-item%
       [label (string-titlecase (symbol->string theme-name))]
       [parent theme-menu]
       [callback (λ (item event)
                   (load-theme theme-name)
                   (save-theme-preference! theme-name)
                   (refresh-theme-colors!)
                   (show-notification! notif-manager 'success 
                                       (format "Theme changed to ~a" theme-name)))]))

(define help-menu (new menu% [label "&Help"] [parent menu-bar]))
(void (new menu-item%
           [label "About"]
           [parent help-menu]
           [callback (λ (item event) (show-about-dialog))]))

;; ============================================================================
;; Top Toolbar Panel
;; ============================================================================

(define toolbar-panel
  (new horizontal-panel%
       [parent main-frame]
       [stretchable-height #f]
       [alignment '(left center)]
       [min-height 40]))

;; Model selector
(define model-label
  (new message%
       [parent toolbar-panel]
       [label "Model:"]))

(define (fallback-model-ids)
  (with-handlers ([exn:fail? (λ (_) '())])
    (define p (build-path (current-directory) "src" "llm" "default-models.json"))
    (if (file-exists? p)
        (let* ([j (call-with-input-file p read-json)]
               [ms (hash-ref j 'models '())])
          (sort
           (remove-duplicates
            (for/list ([m (in-list ms)]
                       #:when (hash? m))
              (hash-ref m 'id "")))
           string<?))
        '())))

(define (fetch-model-ids)
  ;; Mirror the TUI `/models` behavior: hit the configured /models endpoint.
  (define api-key (or (getenv "OPENAI_API_KEY") ""))
  (define base-url (or (getenv "OPENAI_API_BASE") "https://api.openai.com/v1"))
  (cond
    [(string=? (string-trim api-key) "")
     (fallback-model-ids)]
    [else
     (define models (fetch-models-from-endpoint base-url api-key))
     (define ids
       (for/list ([m (in-list models)])
         (cond
           [(hash? m) (hash-ref m 'id (hash-ref m 'name "unknown"))]
           [(string? m) m]
           [else "unknown"])))
     (sort (remove-duplicates ids) string<?)]))

(define model-choice
  (new choice%
       [parent toolbar-panel]
       [label #f]
       [choices '()] ; populated at startup via `refresh-models!`
       [min-width 180]
       [callback (λ (choice event)
                   (define sel (send choice get-string-selection))
                   (when (and sel (not (string=? sel "")))
                     (current-model sel)))]))

(define (refresh-models! #:show-errors? [show-errors? #f])
  (with-handlers ([exn:fail?
                   (λ (e)
                     (when show-errors?
                       (message-box "Models"
                                    (format "Failed to fetch models:\n~a" (exn-message e))
                                    main-frame
                                    '(ok stop)))
                     (define ids (fallback-model-ids))
                     (send model-choice clear)
                     (for ([m (in-list ids)]) (send model-choice append m)))])
    (define ids (fetch-model-ids))
    (send model-choice clear)
    (for ([m (in-list ids)]) (send model-choice append m))
    (define cur (current-model))
    (cond
      [(and cur (member cur ids))
       (send model-choice set-string-selection cur)]
      [(pair? ids)
       (send model-choice set-selection 0)
       (current-model (first ids))])))

(void
 (new button%
      [parent toolbar-panel]
      [label "Refresh"]
      [min-width 70]
      [callback (λ (_b _e) (refresh-models! #:show-errors? #t))]))

;; Spacer
(void (new message% [parent toolbar-panel] [label "    "]))

;; Mode selector
(void (new message%
           [parent toolbar-panel]
           [label "Mode:"]))

(define mode-choice
  (new choice%
       [parent toolbar-panel]
       [label #f]
       [choices '("ask" "architect" "code" "semantic")]
       [selection 2]  ; default to 'code'
       [callback (λ (choice event)
                   (define modes '(ask architect code semantic))
                   (current-mode (list-ref modes (send choice get-selection)))
                   (update-mode-context!))]))

;; Spacer
(void (new message% [parent toolbar-panel] [label "    "]))

;; Priority selector
(void (new message%
           [parent toolbar-panel]
           [label "Priority:"]))
(define priority-choice
  (new choice%
       [parent toolbar-panel]
       [label #f]
       [choices '("best" "fast" "cheap" "verbose")]
       [selection 0]  ; default to 'best'
       [callback (λ (choice event)
                   (define priorities '("best" "fast" "cheap" "verbose"))
                   (define sel (list-ref priorities (send choice get-selection)))
                   (gui-priority sel)
                   ;; Update context
                   (define db (load-ctx))
                   (define ctx (ctx-get-active))
                   (save-ctx!
                    (hash-set db 'items
                              (hash-set (hash-ref db 'items)
                                       (hash-ref db 'active)
                                       (struct-copy Ctx ctx [priority (string->symbol sel)])))))]))
;; Set initial priority from context
(let ([ctx (ctx-get-active)])
  (define ctx-priority (symbol->string (Ctx-priority ctx)))
  (define priorities '("best" "fast" "cheap" "verbose"))
  (define idx (for/or ([p priorities] [i (in-naturals)])
                (and (equal? p ctx-priority) i)))
  (when idx (send priority-choice set-selection idx)))

;; Spacer
(void (new message% [parent toolbar-panel] [label "    "]))

;; Judge toggle
(define judge-checkbox
  (new check-box%
       [parent toolbar-panel]
       [label "LLM Judge"]
       [value (gui-llm-judge)]
       [callback (λ (cb event)
                   (gui-llm-judge (send cb get-value)))]))
;; Set initial judge state from env
(send judge-checkbox set-value (gui-llm-judge))

;; Spacer
(void (new message% [parent toolbar-panel] [label "    "]))

;; Session display with clickable chooser
(define session-panel
  (new horizontal-panel%
       [parent toolbar-panel]
       [stretchable-width #f]
       [alignment '(left center)]))

(define session-label
  (new message%
       [parent session-panel]
       [label "Session: default"]
       [auto-resize #t]))

(define session-chooser-button
  (new button%
       [parent session-panel]
       [label "▼"]
       [min-width 25]
       [min-height 25]
       [callback (λ (b e) (show-session-chooser!))]))

;; Right-aligned status
(define status-panel
  (new horizontal-panel%
       [parent toolbar-panel]
       [alignment '(right center)]
       [stretchable-width #t]))

(define cost-label
  (new message%
       [parent status-panel]
       [label "Cost: $0.0000"]
       [auto-resize #t]))

(define tokens-label
  (new message%
       [parent status-panel]
       [label "Tokens: 0"]
       [auto-resize #t]))

;; ============================================================================
;; Main Content Area
;; ============================================================================

(define content-panel
  (new vertical-panel%
       [parent main-frame]
       [style '(border)]))

;; Chat display area
(define chat-canvas
  (new editor-canvas%
       [parent content-panel]
       [style '(no-hscroll auto-vscroll)]))

(define chat-text
  (new text%
       [auto-wrap #t]))

(send chat-canvas set-editor chat-text)
(send chat-text lock #t)

;; ============================================================================
;; Input Area
;; ============================================================================

(define input-panel
  (new horizontal-panel%
       [parent main-frame]
       [stretchable-height #f]
       [min-height 80]
       [alignment '(left bottom)]))

(define input-canvas
  (new editor-canvas%
       [parent input-panel]
       [min-height 60]
       [style '(no-hscroll)]))

(define input-text
  (new text%
       [auto-wrap #t]))

(send input-canvas set-editor input-text)

;; Override key handler for Shift+Enter / Enter behavior
(define input-keymap (send input-text get-keymap))
(send input-keymap add-function "send-message"
      (λ (editor event)
        (send-user-message!)))
(send input-keymap map-function "return" "send-message")

;; Button panel
(define button-panel
  (new vertical-panel%
       [parent input-panel]
       [stretchable-width #f]
       [alignment '(center center)]))

(void
 (new button%
      [parent button-panel]
      [label "Send"]
      [min-width 80]
      [callback (λ (button event) (send-user-message!))]))

(void
 (new button%
      [parent button-panel]
      [label "Attach"]
      [min-width 80]
      [callback (λ (button event) (attach-file!))]))

;; ============================================================================
;; Status Bar
;; ============================================================================

(define status-bar
  (new message%
       [parent main-frame]
       [label "Ready"]
       [stretchable-width #t]
       [auto-resize #f]))

;; ============================================================================
;; Chat Functions
;; ============================================================================

(define (append-message! role content)
  (when (and content (string? content))
    (send chat-text lock #f)
    (define start-pos (send chat-text last-position))
    
    ;; Add role header
    (define header
      (case role
        [(user) "\n[USER]\n"]
        [(assistant) "\n[ASSISTANT]\n"]
        [(system) "\n[SYSTEM]\n"]
        [else "\n"]))
    
    (send chat-text insert header)
    (send chat-text insert content)
    (send chat-text insert "\n")
    
    ;; Style the header
    (define header-end (+ start-pos (string-length header)))
    (define style-delta (new style-delta%))
    (send style-delta set-weight-on 'bold)
    (case role
      [(user) (send style-delta set-delta-foreground (make-object color% 100 200 255))]
      [(assistant) (send style-delta set-delta-foreground (make-object color% 150 255 150))]
      [(system) (send style-delta set-delta-foreground (make-object color% 255 200 100))])
    (send chat-text change-style style-delta start-pos header-end)
    
    (send chat-text lock #t)
    (send chat-text scroll-to-position (send chat-text last-position))))

(define (clear-chat!)
  (send chat-text lock #f)
  (send chat-text erase)
  (send chat-text lock #t)
  (set-box! session-cost 0.0)
  (set-box! session-tokens 0)
  (update-status-display!))

(define (update-status-display!)
  (send cost-label set-label (format "Cost: $~a" (real->decimal-string (unbox session-cost) 4)))
  (send tokens-label set-label (format "Tokens: ~a" (unbox session-tokens))))

(define (set-status! msg)
  (send status-bar set-label msg))

;; ============================================================================
;; Message Handling
;; ============================================================================

(define current-attachments (box '()))

(define (attach-file!)
  (define path (get-file "Select file to attach" main-frame))
  (when path
    (define content (file->string path))
    (set-box! current-attachments (cons (list 'file (path->string path) content) (unbox current-attachments)))
    (define filename (path->string (file-name-from-path path)))
    (set-status! (format "Attached: ~a" filename))
    (show-notification! notif-manager 'info (format "Attached: ~a" filename) #:duration 2000)))

(define (send-user-message!)
  (define content (send input-text get-text))
  (when (and content (not (string=? (string-trim content) "")))
    (send input-text erase)
    
    ;; Generate session title after first message
    (when (not (unbox first-message-sent?))
      (set-box! first-message-sent? #t)
      (thread
       (λ ()
         (with-handlers ([exn:fail? (λ (e) (void))])
           ;; Try to generate title using cheap model
           (define api-key (or (getenv "OPENAI_API_KEY") ""))
           (when (not (string=? api-key ""))
             (define openai-mod (dynamic-require 'chrysalis-forge/src/llm/openai-client #f))
             (define make-sender (dynamic-require 'chrysalis-forge/src/llm/openai-client 'make-openai-sender))
             (define base-url (or (getenv "OPENAI_API_BASE") "https://api.openai.com/v1"))
             (define sender (make-sender #:model "gpt-4o-mini" #:api-key api-key #:api-base base-url))
             (define prompt (format "Generate a concise, descriptive title (3-8 words) for this conversation based on the user's first message. Return only the title, no quotes or explanation.\n\nUser message: ~a" 
                                    (if (> (string-length content) 200)
                                        (string-append (substring content 0 200) "...")
                                        content)))
             (define-values (ok? title-text usage) (sender prompt))
             (when ok?
               ;; Handle response - sender uses json_object format, so content might be JSON string
               (define title-str
                 (cond
                   [(string? title-text)
                    ;; Try to parse as JSON first (since response_format is json_object)
                    (with-handlers ([exn:fail? (λ (_) title-text)])
                      (define parsed (string->jsexpr title-text))
                      (if (hash? parsed)
                          ;; Extract from common JSON keys
                          (or (hash-ref parsed 'title #f)
                              (hash-ref parsed 'text #f)
                              (hash-ref parsed 'content #f)
                              title-text)
                          title-text))]
                   [(hash? title-text)
                    ;; If it's already a hash, extract from common keys
                    (or (hash-ref title-text 'title #f)
                        (hash-ref title-text 'text #f)
                        (hash-ref title-text 'content #f)
                        (jsexpr->string title-text))]
                   [else (format "~a" title-text)]))
               (when (and title-str (string? title-str))
                 (define clean-title (string-trim title-str))
                 (when (> (string-length clean-title) 0)
                   ;; Remove quotes if present
                   (define final-title
                     (if (and (> (string-length clean-title) 2)
                              (equal? (substring clean-title 0 1) "\"")
                              (equal? (substring clean-title (sub1 (string-length clean-title))) "\""))
                         (substring clean-title 1 (sub1 (string-length clean-title)))
                         clean-title))
                   (when (> (string-length final-title) 0)
                     (queue-callback
                      (λ ()
                        (define db (load-ctx))
                        (define active-name (hash-ref db 'active))
                        (session-update-title! active-name final-title)
                        (update-session-label!))))))))))))
    
    ;; Display user message
    (append-message! 'user content)
    (set-status! "Thinking...")
    
    ;; Process in background thread
    (thread
     (λ ()
       (with-handlers ([exn:fail?
                        (λ (e)
                          (queue-callback
                           (λ ()
                             (append-message! 'system (format "Error: ~a" (exn-message e)))
                             (set-status! "Error")
                             (show-notification! notif-manager 'error 
                                                 (format "Request failed: ~a" 
                                                         (if (> (string-length (exn-message e)) 50)
                                                             (string-append (substring (exn-message e) 0 50) "...")
                                                             (exn-message e)))))))])
         (process-message! content))))))

(define (process-message! content)
  ;; Build attachments string if any
  (define attach-str
    (if (null? (unbox current-attachments))
        ""
        (string-append
         "\n\n<attachments>\n"
         (string-join
          (for/list ([a (unbox current-attachments)])
            (match a
              [(list 'file path content)
               (format "File: ~a\n```\n~a\n```" path content)]
              [_ ""]))
          "\n")
         "\n</attachments>")))
  
  ;; Clear attachments
  (set-box! current-attachments '())
  
  ;; Get context
  (define ctx (ctx-get-active))
  (define full-prompt (string-append content attach-str))
  
  ;; Build messages
  (define history (Ctx-history ctx))
  (define messages
    (append
     (if (null? history)
         (list (hash 'role "system" 'content (Ctx-system ctx)))
         history)
     (list (hash 'role "user" 'content full-prompt))))
  
  ;; Stream response
  (define response-buffer (box ""))
  
  ;; Use dynamic require to get the sender
  (define openai-mod (dynamic-require 'chrysalis-forge/src/llm/openai-client #f))
  (define make-sender (dynamic-require 'chrysalis-forge/src/llm/openai-client 'make-openai-sender))
  
  (define api-key (or (getenv "OPENAI_API_KEY") ""))
  (define base-url (gui-base-url))  ; Use GUI config parameter
  
  (define sender
    (make-sender #:model (current-model) #:api-key api-key #:api-base base-url))
  
  ;; Call the sender (non-streaming for simplicity)
  (define-values (ok? result usage) (sender messages))
  
  (if ok?
      (let ()
        ;; Handle result - might be JSON string if response_format is json_object
        (define response-text
          (cond
            [(string? result)
             ;; Try to parse as JSON first (since response_format is json_object)
             (with-handlers ([exn:fail? (λ (_) result)])
               (define parsed (string->jsexpr result))
               (if (hash? parsed)
                   ;; Extract from common JSON keys, or use the whole thing as string
                   (or (hash-ref parsed 'content #f)
                       (hash-ref parsed 'text #f)
                       (hash-ref parsed 'message #f)
                       (jsexpr->string parsed))
                   result))]
            [(hash? result)
             ;; If it's already a hash, extract content
             (or (hash-ref result 'content #f)
                 (hash-ref result 'text #f)
                 (jsexpr->string result))]
            [else (format "~a" result)]))
        
        ;; Update stats
        (when (hash? usage)
          (define tokens-in (hash-ref usage 'prompt_tokens 0))
          (define tokens-out (hash-ref usage 'completion_tokens 0))
          (define total-tokens (hash-ref usage 'total_tokens 0))
          (set-box! session-tokens
                    (+ (unbox session-tokens) total-tokens))
          (set-box! session-cost
                    (+ (unbox session-cost)
                       (calculate-cost (current-model) tokens-in tokens-out))))
        
        ;; Update context with history
        (define new-history
          (append messages (list (hash 'role "assistant" 'content response-text))))
        (define db (load-ctx))
        (save-ctx!
         (hash-set db 'items
                   (hash-set (hash-ref db 'items)
                             (hash-ref db 'active)
                             (struct-copy Ctx ctx [history new-history]))))
        
        ;; Display response
        (queue-callback
         (λ ()
           (append-message! 'assistant response-text)
           (update-status-display!)
           (set-status! "Ready"))))
      
      (queue-callback
       (λ ()
         (append-message! 'system (format "API Error: ~a" result))
         (set-status! "Error")
         (show-notification! notif-manager 'error "API request failed")))))

;; ============================================================================
;; Session Management
;; ============================================================================

(define (update-session-label!)
  (define db (load-ctx))
  (define active-name (hash-ref db 'active))
  (define metadata (hash-ref db 'metadata (hash)))
  (define meta (hash-ref metadata active-name (hash)))
  (define title (hash-ref meta 'title #f))
  (define session-id (hash-ref meta 'id (symbol->string active-name)))
  
  (if title
      (send session-label set-label (format "Session: ~a" title))
      (send session-label set-label (format "Session: ~a" session-id))))

(define (update-mode-context!)
  (define db (load-ctx))
  (define ctx (ctx-get-active))
  (save-ctx!
   (hash-set db 'items
             (hash-set (hash-ref db 'items)
                       (hash-ref db 'active)
                       (struct-copy Ctx ctx [mode (current-mode)])))))

(define (new-session-dialog)
  (define dialog (new dialog% [label "New Session"] [parent main-frame] [width 300] [height 150]))
  (define name-field (new text-field% [parent dialog] [label "Session Name (optional):"]))
  
  (define mode-panel (new horizontal-panel% [parent dialog] [stretchable-height #f]))
  (new message% [parent mode-panel] [label "Mode:"])
  (define mode-selector
    (new choice%
         [parent mode-panel]
         [label #f]
         [choices '("ask" "architect" "code" "semantic")]
         [selection 2]))
  
  (define button-panel (new horizontal-panel% [parent dialog] [alignment '(right center)]))
  (new button%
       [parent button-panel]
       [label "Cancel"]
       [callback (λ (b e) (send dialog show #f))])
  (new button%
       [parent button-panel]
       [label "Create"]
       [callback (λ (b e)
                   (define name (send name-field get-value))
                   (define modes '(ask architect code semantic))
                   (define mode (list-ref modes (send mode-selector get-selection)))
                   (with-handlers ([exn:fail?
                                    (λ (e) (message-box "Error" (exn-message e) dialog '(ok stop)))])
                     ;; Create session with auto-generated ID if no name provided
                     (if (and name (not (string=? (string-trim name) "")))
                         (begin
                           (session-create! name mode)
                           (session-switch! name))
                         (let* ([session-id (generate-session-id)]
                                [session-name (string->symbol (format "session-~a" session-id))])
                           (session-create! session-name mode #:id session-id)
                           (session-switch! session-name)))
                     (set-box! first-message-sent? #f) ; Reset for new session
                      (update-session-label!)
                      (clear-chat!)
                      (show-notification! notif-manager 'success "New session created")
                      (send dialog show #f)))])
  
  (send dialog show #t))

(define (show-session-chooser!)
  "Show a dialog to choose or manage sessions, sorted by last accessed"
  (define sessions (session-list-with-metadata))
  
  ;; Sort by updated_at (most recent first), then by created_at
  (define sorted-sessions
    (sort sessions >
          #:key (λ (s)
                  (or (hash-ref s 'updated_at #f)
                      (hash-ref s 'created_at #f)
                      0))))
  
  (define dialog (new dialog% [label "Sessions"] [parent main-frame] [width 500] [height 400]))
  
  ;; Create a list box with custom display
  (define list-box
    (new list-box%
         [parent dialog]
         [label "Sessions (sorted by last accessed):"]
         [choices (for/list ([s sorted-sessions])
                    (define id (hash-ref s 'id))
                    (define title (hash-ref s 'title))
                    (define created (hash-ref s 'created_at))
                    (define is-active (hash-ref s 'is_active))
                    (define date-str
                      (if created
                          (date->string (seconds->date created) #t)
                          "Unknown"))
                    (format "~a ~a~a~a"
                            (if is-active "*" " ")
                            (or title id)
                            (if title (format " (~a)" id) "")
                            (format " - ~a" date-str)))]
         [style '(single)]
         [selection (for/or ([s sorted-sessions] [i (in-naturals)])
                      (and (hash-ref s 'is_active #f) i))]))
  
  ;; Button panel
  (define button-panel (new horizontal-panel% [parent dialog] [alignment '(right center)]))
  
  (new button%
       [parent button-panel]
       [label "New Session"]
       [callback (λ (b e)
                   (send dialog show #f)
                   (new-session-dialog))])
  
  (new button%
       [parent button-panel]
       [label "Delete"]
       [callback (λ (b e)
                   (define sel (send list-box get-selection))
                   (when sel
                     (define session (list-ref sorted-sessions sel))
                     (define name (hash-ref session 'name))
                     (define is-active (hash-ref session 'is_active))
                     (if is-active
                         (message-box "Error" "Cannot delete the active session" dialog '(ok stop))
                         (when (eq? 'yes (message-box "Confirm" 
                                                      (format "Delete session '~a'?" name)
                                                      dialog
                                                      '(yes-no caution)))
                           (with-handlers ([exn:fail?
                                             (λ (e) (message-box "Error" (exn-message e) dialog '(ok stop)))])
                              (session-delete! name)
                              (show-notification! notif-manager 'warning "Session deleted")
                              (send dialog show #f)
                              (show-session-chooser!))))))])
  
  (new button%
       [parent button-panel]
       [label "Cancel"]
       [callback (λ (b e) (send dialog show #f))])
  
  (new button%
       [parent button-panel]
       [label "Switch"]
       [callback (λ (b e)
                   (define sel (send list-box get-selection))
                   (when sel
                     (define session (list-ref sorted-sessions sel))
                     (define name (hash-ref session 'name))
                     (define title (hash-ref session 'title))
                     (session-switch! name)
                     (set-box! first-message-sent? #f) ; Reset for switched session
                     (update-session-label!)
                     (clear-chat!)
                     (load-chat-history!)
                     (show-notification! notif-manager 'success 
                                         (format "Switched to ~a" (or title name)))
                     (send dialog show #f)))])
  
  (send dialog show #t))

(define (switch-session-dialog)
  "Legacy function - redirects to new chooser"
  (show-session-chooser!))

(define (load-chat-history!)
  (define ctx (ctx-get-active))
  (define history (Ctx-history ctx))
  (for ([msg history])
    (define role (hash-ref msg 'role ""))
    (define content (hash-ref msg 'content ""))
    (when (and (string? role) (string? content) (not (string=? role "system")) (not (string=? content "")))
      (append-message! (string->symbol role) content))))

;; ============================================================================
;; Configuration Dialog
;; ============================================================================

(define (show-config-dialog)
  (define dialog (new dialog% [label "Configuration"] [parent main-frame] [width 500] [height 600]))
  (define v-panel (new vertical-panel% [parent dialog] [alignment '(left top)] [spacing 10]))
  
  ;; Model
  (define model-panel (new horizontal-panel% [parent v-panel] [stretchable-height #f]))
  (new message% [parent model-panel] [label "Model:"])
  (define model-field (new text-field% [parent model-panel] [label #f] [min-width 200]
                           [init-value (current-model)]))
  
  ;; Vision Model
  (define vision-panel (new horizontal-panel% [parent v-panel] [stretchable-height #f]))
  (new message% [parent vision-panel] [label "Vision Model:"])
  (define vision-field (new text-field% [parent vision-panel] [label #f] [min-width 200]
                             [init-value (gui-vision-model)]))
  
  ;; Judge Model
  (define judge-model-panel (new horizontal-panel% [parent v-panel] [stretchable-height #f]))
  (new message% [parent judge-model-panel] [label "Judge Model:"])
  (define judge-model-field (new text-field% [parent judge-model-panel] [label #f] [min-width 200]
                                 [init-value (gui-judge-model)]))
  
  ;; Base URL
  (define url-panel (new horizontal-panel% [parent v-panel] [stretchable-height #f]))
  (new message% [parent url-panel] [label "Base URL:"])
  (define url-field (new text-field% [parent url-panel] [label #f] [min-width 300]
                         [init-value (gui-base-url)]))
  
  ;; Budget
  (define budget-panel (new horizontal-panel% [parent v-panel] [stretchable-height #f]))
  (new message% [parent budget-panel] [label "Budget ($):"])
  (define budget-field (new text-field% [parent budget-panel] [label #f] [min-width 150]
                            [init-value (if (= (gui-budget) +inf.0) "" (number->string (gui-budget)))]))
  
  ;; Timeout
  (define timeout-panel (new horizontal-panel% [parent v-panel] [stretchable-height #f]))
  (new message% [parent timeout-panel] [label "Timeout (seconds):"])
  (define timeout-field (new text-field% [parent timeout-panel] [label #f] [min-width 150]
                             [init-value (if (= (gui-timeout) +inf.0) "" (number->string (gui-timeout)))]))
  
  ;; Security Level
  (define security-panel (new horizontal-panel% [parent v-panel] [stretchable-height #f]))
  (new message% [parent security-panel] [label "Security Level:"])
  (define security-choice
    (new choice%
         [parent security-panel]
         [label #f]
         [choices '("0" "1" "2" "3" "god")]
         [selection (min (gui-security-level) 4)]))
  
  ;; Debug Level
  (define debug-panel (new horizontal-panel% [parent v-panel] [stretchable-height #f]))
  (new message% [parent debug-panel] [label "Debug Level:"])
  (define debug-choice
    (new choice%
         [parent debug-panel]
         [label #f]
         [choices '("0" "1" "2")]
         [selection (min (gui-debug-level) 2)]))
  
  ;; Pretty
  (define pretty-panel (new horizontal-panel% [parent v-panel] [stretchable-height #f]))
  (new message% [parent pretty-panel] [label "Pretty Output:"])
  (define pretty-choice
    (new choice%
         [parent pretty-panel]
         [label #f]
         [choices '("none" "glow")]
         [selection (if (equal? (gui-pretty) "glow") 1 0)]))
  
  ;; Buttons
  (define button-panel (new horizontal-panel% [parent dialog] [alignment '(right center)]))
  (new button%
       [parent button-panel]
       [label "Cancel"]
       [callback (λ (b e) (send dialog show #f))])
  (new button%
       [parent button-panel]
       [label "Save"]
       [callback (λ (b e)
                   (with-handlers ([exn:fail?
                                    (λ (e) (message-box "Error" (exn-message e) dialog '(ok stop)))])
                     ;; Update parameters
                     (current-model (send model-field get-value))
                     (gui-vision-model (send vision-field get-value))
                     (gui-judge-model (send judge-model-field get-value))
                     (gui-base-url (send url-field get-value))
                     
                     (define budget-str (send budget-field get-value))
                     (gui-budget (if (string=? budget-str "") +inf.0 (string->number budget-str)))
                     
                     (define timeout-str (send timeout-field get-value))
                     (gui-timeout (if (string=? timeout-str "") +inf.0 (string->number timeout-str)))
                     
                     (define security-val (send security-choice get-selection))
                     (gui-security-level (if (= security-val 4) 4 security-val))
                     
                     (gui-debug-level (send debug-choice get-selection))
                     (gui-pretty (list-ref '("none" "glow") (send pretty-choice get-selection)))
                     
                     ;; Update model choice in toolbar
                     (define model-val (current-model))
                     (define model-ids (fetch-model-ids))
                     (when (member model-val model-ids)
                       (send model-choice set-string-selection model-val))
                     
                     (message-box "Success" "Configuration saved." dialog '(ok))
                     (send dialog show #f)))])
  
  (send dialog show #t))

;; ============================================================================
;; Workflows Dialog
;; ============================================================================

(define (show-workflows-dialog)
  (define dialog (new dialog% [label "Workflows"] [parent main-frame] [width 600] [height 500]))
  (define v-panel (new vertical-panel% [parent dialog] [alignment '(left top)] [spacing 10]))
  
  ;; List box for workflows
  (define list-box
    (new list-box%
         [parent v-panel]
         [label "Available Workflows:"]
         [choices '()]
         [style '(single)]
         [min-height 300]))
  
  (define (refresh-workflows!)
    (with-handlers ([exn:fail?
                     (λ (e)
                       (message-box "Error" (format "Failed to load workflows: ~a" (exn-message e)) dialog '(ok stop)))])
      (define workflows-json (workflow-list))
      (define workflows (string->jsexpr workflows-json))
      (send list-box clear)
      (for ([w workflows])
        (define slug (hash-ref w 'slug "unknown"))
        (define desc (hash-ref w 'description "No description"))
        (send list-box append (format "~a - ~a" slug desc))))
    (when (= (send list-box get-number) 0)
      (send list-box append "No workflows found")))
  
  (refresh-workflows!)
  
  ;; Button panel
  (define button-panel (new horizontal-panel% [parent dialog] [alignment '(right center)]))
  
  (new button%
       [parent button-panel]
       [label "Show Details"]
       [callback (λ (b e)
                   (define sel (send list-box get-selection))
                   (when sel
                     (define text (send list-box get-string sel))
                     (define slug (first (string-split text " - ")))
                     (with-handlers ([exn:fail?
                                      (λ (e) (message-box "Error" (exn-message e) dialog '(ok stop)))])
                       (define content (workflow-get slug))
                       (if (equal? content "null")
                           (message-box "Not Found" (format "Workflow '~a' not found." slug) dialog '(ok))
                           (show-workflow-details-dialog slug content)))))])
  
  (new button%
       [parent button-panel]
       [label "Delete"]
       [callback (λ (b e)
                   (define sel (send list-box get-selection))
                   (when sel
                     (define text (send list-box get-string sel))
                     (define slug (first (string-split text " - ")))
                     (when (eq? 'yes (message-box "Confirm"
                                                   (format "Delete workflow '~a'?" slug)
                                                   dialog
                                                   '(yes-no caution)))
                       (with-handlers ([exn:fail?
                                        (λ (e) (message-box "Error" (exn-message e) dialog '(ok stop)))])
                         (workflow-delete slug)
                         (refresh-workflows!)))))])
  
  (new button%
       [parent button-panel]
       [label "Refresh"]
       [callback (λ (b e) (refresh-workflows!))])
  
  (new button%
       [parent button-panel]
       [label "Close"]
       [callback (λ (b e) (send dialog show #f))])
  
  (send dialog show #t))

(define (show-workflow-details-dialog slug content)
  (define dialog (new dialog% [label (format "Workflow: ~a" slug)] [parent main-frame] [width 700] [height 500]))
  (define v-panel (new vertical-panel% [parent dialog] [alignment '(left top)] [spacing 10]))
  
  (new message% [parent v-panel] [label (format "Slug: ~a" slug)] [auto-resize #t])
  
  (define text-editor (new text%))
  (send text-editor insert content)
  (send text-editor lock #t)
  
  (define editor-canvas
    (new editor-canvas%
         [parent v-panel]
         [editor text-editor]
         [style '(no-hscroll auto-vscroll)]
         [min-height 400]))
  
  (define button-panel (new horizontal-panel% [parent dialog] [alignment '(right center)]))
  (new button%
       [parent button-panel]
       [label "Close"]
       [callback (λ (b e) (send dialog show #f))])
  
  (send dialog show #t))

;; ============================================================================
;; Raco Command Dialog
;; ============================================================================

(define (show-raco-dialog)
  (define dialog (new dialog% [label "Run Raco Command"] [parent main-frame] [width 500] [height 200]))
  (define v-panel (new vertical-panel% [parent dialog] [alignment '(left top)] [spacing 10]))
  
  (new message% [parent v-panel] [label "Enter raco command arguments:"])
  
  (define cmd-field (new text-field% [parent v-panel] [label "raco "] [min-width 400]))
  
  (define output-text (new text%))
  (define output-canvas
    (new editor-canvas%
         [parent v-panel]
         [editor output-text]
         [style '(no-hscroll auto-vscroll)]
         [min-height 100]))
  
  (define button-panel (new horizontal-panel% [parent dialog] [alignment '(right center)]))
  (new button%
       [parent button-panel]
       [label "Run"]
       [callback (λ (b e)
                   (define args (send cmd-field get-value))
                   (send output-text lock #f)
                   (send output-text erase)
                   (send output-text insert (format "Running: raco ~a\n\n" args))
                   (with-handlers ([exn:fail?
                                    (λ (e)
                                      (send output-text insert (format "Error: ~a\n" (exn-message e))))])
                     (define result (with-output-to-string
                                      (λ () (system (format "raco ~a" args)))))
                     (send output-text insert result))
                   (send output-text lock #t)
                   (send output-text scroll-to-position (send output-text last-position)))])
  
  (new button%
       [parent button-panel]
       [label "Close"]
       [callback (λ (b e) (send dialog show #f))])
  
  (send dialog show #t))

;; ============================================================================
;; Init Project
;; ============================================================================

(define (init-project!)
  (define result (message-box "Initialize Project"
                              "This will analyze the codebase and create/update agents.md.\n\nContinue?"
                              main-frame
                              '(yes-no)))
  (when (eq? result 'yes)
    (define init-prompt #<<EOF
Analyze this codebase and create/update **agents.md** to help future agents work effectively in this repository.

**First**: Check if directory is empty or only contains config files. If so, stop and say "Directory appears empty or only contains config. Add source code first, then run this command to generate agents.md."

**Goal**: Document what an agent needs to know to work in this codebase - commands, patterns, conventions, gotchas.

**Discovery process**:

1. Check directory contents with `ls`
2. Look for existing rule files (`.cursor/rules/*.md`, `.cursorrules`, `.github/copilot-instructions.md`, `claude.md`, `agents.md`) - only read if they exist
3. Identify project type from config files and directory structure
4. Find build/test/lint commands from config files, scripts, Makefiles, or CI configs
5. Read representative source files to understand code patterns
6. If agents.md exists, read and improve it

**Content to include**:

- Essential commands (build, test, run, deploy, etc.) - whatever is relevant for this project
- Code organization and structure
- Naming conventions and style patterns
- Testing approach and patterns
- Important gotchas or non-obvious patterns
- Any project-specific context from existing rule files

**Format**: Clear markdown sections. Use your judgment on structure based on what you find. Aim for completeness over brevity - include everything an agent would need to know.

**Critical**: Only document what you actually observe. Never invent commands, patterns, or conventions. If you can't find something, don't include it.
EOF
)
    ;; Send as a regular message to the agent
    (send input-text insert init-prompt)
    (send-user-message!)))

;; ============================================================================
;; About Dialog
;; ============================================================================

(define (show-about-dialog)
  (message-box
   "About Chrysalis Forge"
   "Chrysalis Forge GUI\n\nAn AI Agent Framework with LLM Integration\n\nVersion 0.1.0"
   main-frame
   '(ok)))

;; ============================================================================
;; Main Entry Point
;; ============================================================================

(define (run-gui!)
  (load-dotenv!)
  
  ;; Theme is already loaded by theme-system.rkt init-theme!
  ;; Apply to frame on startup
  (refresh-theme-colors!)
  
  ;; Always create a new session on startup (don't reuse old sessions)
  ;; Users can explicitly resume sessions via the session chooser
  (define session-id (generate-session-id))
  (define session-name (string->symbol (format "session-~a" session-id)))
  (session-create! session-name 'code #:id session-id)
  (session-switch! session-name)
  
  (update-session-label!)
  (set-box! first-message-sent? #f) ; Reset for new session

  ;; Populate models list (same source as TUI `/models`)
  (refresh-models!)
  
  ;; Welcome message with current theme info
  (define current-theme-name (hash-ref (current-gui-theme) 'name 'dark))
  (append-message! 'system 
                   (format "Welcome to Chrysalis Forge!\n\nType your message and press Enter to send.\nUse the toolbar to change models or modes.\n\nTheme: ~a (change via Tools → Theme)"
                           current-theme-name))
  
  ;; Show welcome notification
  (show-notification! notif-manager 'info "Ready to assist!" #:duration 2000)
  
  ;; Don't load old history - start fresh each time
  ;; Users can explicitly resume sessions via the session chooser
  
  (send main-frame show #t))

;; Allow direct execution
(module+ main
  (run-gui!))
