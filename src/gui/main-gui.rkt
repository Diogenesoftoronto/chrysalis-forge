#lang racket/gui

(require racket/class racket/string racket/format racket/list racket/file json
         "../stores/context-store.rkt"
         "../llm/dspy-core.rkt"
         "../utils/dotenv.rkt"
         "../llm/model-registry.rkt")

(provide run-gui!)

;; ============================================================================
;; Parameters & State
;; ============================================================================

(define current-model (make-parameter (or (getenv "MODEL") "gpt-5.2")))
(define current-mode (make-parameter 'code))
(define session-cost (box 0.0))
(define session-tokens (box 0))

;; ============================================================================
;; Theme Colors
;; ============================================================================

(define bg-color (make-object color% 30 30 35))
(define fg-color (make-object color% 220 220 220))
(define accent-color (make-object color% 100 149 237))
(define user-msg-bg (make-object color% 45 45 55))
(define assistant-msg-bg (make-object color% 35 50 60))
(define input-bg (make-object color% 40 40 48))
(define button-bg (make-object color% 60 60 70))

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

(define model-choice
  (new combo-field%
       [parent toolbar-panel]
       [label #f]
       [choices '("gpt-5.2" "gpt-4.1" "gpt-4.1-mini" "o3" "o4-mini" "claude-sonnet-4-20250514" "gemini-2.5-pro")]
       [init-value (current-model)]
       [min-width 180]
       [callback (λ (field event)
                   (current-model (send field get-value)))]))

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

;; Session display
(define session-label
  (new message%
       [parent toolbar-panel]
       [label "Session: default"]
       [auto-resize #t]))

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
    (set-status! (format "Attached: ~a" (file-name-from-path path)))))

(define (send-user-message!)
  (define content (send input-text get-text))
  (when (and content (not (string=? (string-trim content) "")))
    (send input-text erase)
    
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
                             (set-status! "Error"))))])
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
  (define base-url (or (getenv "OPENAI_API_BASE") "https://api.openai.com/v1"))
  
  (define sender
    (make-sender #:model (current-model) #:api-key api-key #:api-base base-url))
  
  ;; Call the sender (non-streaming for simplicity)
  (define-values (ok? result usage) (sender messages))
  
  (if ok?
      (let ()
        ;; Update stats
        (when (hash? usage)
          (set-box! session-tokens
                    (+ (unbox session-tokens)
                       (hash-ref usage 'total_tokens 0))))
        
        ;; Update context with history
        (define new-history
          (append messages (list (hash 'role "assistant" 'content result))))
        (define db (load-ctx))
        (save-ctx!
         (hash-set db 'items
                   (hash-set (hash-ref db 'items)
                             (hash-ref db 'active)
                             (struct-copy Ctx ctx [history new-history]))))
        
        ;; Display response
        (queue-callback
         (λ ()
           (append-message! 'assistant result)
           (update-status-display!)
           (set-status! "Ready"))))
      
      (queue-callback
       (λ ()
         (append-message! 'system (format "API Error: ~a" result))
         (set-status! "Error")))))

;; ============================================================================
;; Session Management
;; ============================================================================

(define (update-session-label!)
  (define-values (sessions active) (session-list))
  (send session-label set-label (format "Session: ~a" active)))

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
  (define name-field (new text-field% [parent dialog] [label "Session Name:"]))
  
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
                   (when (and name (not (string=? name "")))
                     (define modes '(ask architect code semantic))
                     (define mode (list-ref modes (send mode-selector get-selection)))
                     (with-handlers ([exn:fail?
                                      (λ (e) (message-box "Error" (exn-message e) dialog '(ok stop)))])
                       (session-create! name mode)
                       (session-switch! name)
                       (update-session-label!)
                       (clear-chat!)
                       (send dialog show #f))))])
  
  (send dialog show #t))

(define (switch-session-dialog)
  (define-values (sessions active) (session-list))
  (define session-names (map symbol->string sessions))
  
  (define dialog (new dialog% [label "Switch Session"] [parent main-frame] [width 300] [height 200]))
  
  (define list-box
    (new list-box%
         [parent dialog]
         [label "Sessions:"]
         [choices session-names]
         [selection (index-of session-names (symbol->string active))]))
  
  (define button-panel (new horizontal-panel% [parent dialog] [alignment '(right center)]))
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
                     (session-switch! (list-ref session-names sel))
                     (update-session-label!)
                     (clear-chat!)
                     (load-chat-history!)
                     (send dialog show #f)))])
  
  (send dialog show #t))

(define (load-chat-history!)
  (define ctx (ctx-get-active))
  (define history (Ctx-history ctx))
  (for ([msg history])
    (define role (hash-ref msg 'role ""))
    (define content (hash-ref msg 'content ""))
    (when (and (string? role) (string? content) (not (string=? role "system")) (not (string=? content "")))
      (append-message! (string->symbol role) content))))

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
  (update-session-label!)
  
  ;; Welcome message
  (append-message! 'system "Welcome to Chrysalis Forge!\n\nType your message and press Enter to send.\nUse the toolbar to change models or modes.")
  
  ;; Load existing history
  (load-chat-history!)
  
  (send main-frame show #t))

;; Allow direct execution
(module+ main
  (run-gui!))
