#lang racket/gui

(require racket/class
         racket/string
         racket/date)

(provide chat-widget%
         make-chat-widget
         format-code-block)

(define role-icons
  (hash 'user "👤"
        'assistant "🤖"
        'system "⚙"
        'tool "🔧"))

(define bg-color (make-object color% 30 30 35))
(define fg-color (make-object color% 220 220 220))
(define user-msg-bg (make-object color% 55 75 115))
(define assistant-msg-bg (make-object color% 40 50 55))
(define system-msg-bg (make-object color% 45 45 50))
(define tool-msg-bg (make-object color% 50 55 45))
(define code-bg (make-object color% 25 25 30))
(define border-color (make-object color% 80 80 90))
(define dim-fg (make-object color% 140 140 140))
(define accent-color (make-object color% 100 149 237))

(struct chat-message (role content timestamp id) #:transparent)

(define chat-widget%
  (class object%
    (init-field parent
                [theme #f])
    (super-new)
    
    (define messages '())
    (define message-counter 0)
    (define streaming? #f)
    (define streaming-start-pos 0)
    (define cursor-timer #f)
    (define cursor-visible? #t)
    
    (define main-panel
      (new vertical-panel%
           [parent parent]
           [style '(auto-vscroll)]
           [alignment '(left top)]))
    
    (define chat-text (new text% [auto-wrap #t]))
    (define chat-canvas
      (new editor-canvas%
           [parent main-panel]
           [editor chat-text]
           [style '(no-hscroll auto-vscroll)]
           [min-height 400]))
    
    (send chat-text lock #t)
    
    (define (format-timestamp ts)
      (define d (seconds->date ts))
      (format "~a:~a"
              (~a (date-hour d) #:min-width 2 #:pad-string "0" #:align 'right)
              (~a (date-minute d) #:min-width 2 #:pad-string "0" #:align 'right)))
    
    (define (get-icon role)
      (hash-ref role-icons role "•"))
    
    (define (get-role-bg role)
      (case role
        [(user) user-msg-bg]
        [(assistant) assistant-msg-bg]
        [(system) system-msg-bg]
        [(tool) tool-msg-bg]
        [else assistant-msg-bg]))
    
    (define (render-message msg)
      (define role (chat-message-role msg))
      (define content (chat-message-content msg))
      (define ts (chat-message-timestamp msg))
      (define msg-id (chat-message-id msg))
      
      (send chat-text lock #f)
      (define start-pos (send chat-text last-position))
      
      (define icon (get-icon role))
      (define time-str (format-timestamp ts))
      
      (cond
        [(eq? role 'system)
         (send chat-text insert "\n")
         (define center-start (send chat-text last-position))
         (send chat-text insert (format "~a ~a  [~a]\n" icon content time-str))
         (define center-end (send chat-text last-position))
         (define dim-style (new style-delta%))
         (send dim-style set-delta-foreground dim-fg)
         (send dim-style set-size-mult 0.9)
         (send chat-text change-style dim-style center-start center-end)]
        
        [else
         (send chat-text insert "\n")
         (define header-start (send chat-text last-position))
         
         (define role-name
           (case role
             [(user) "You"]
             [(assistant) "Assistant"]
             [(tool) "Tool"]
             [else (symbol->string role)]))
         
         (send chat-text insert (format "~a ~a" icon role-name))
         (define header-end (send chat-text last-position))
         
         (send chat-text insert (format "  ~a  " time-str))
         (define time-end (send chat-text last-position))
         
         (send chat-text insert "[copy]")
         (define copy-end (send chat-text last-position))
         
         (send chat-text insert "\n")
         
         (define header-style (new style-delta%))
         (send header-style set-weight-on 'bold)
         (send header-style set-delta-foreground
               (case role
                 [(user) accent-color]
                 [(assistant) (make-object color% 120 200 120)]
                 [(tool) (make-object color% 200 180 100)]
                 [else fg-color]))
         (send chat-text change-style header-style header-start header-end)
         
         (define time-style (new style-delta%))
         (send time-style set-delta-foreground dim-fg)
         (send chat-text change-style time-style header-end time-end)
         
         (define copy-style (new style-delta%))
         (send copy-style set-delta-foreground (make-object color% 100 120 180))
         (send copy-style set-underlined-on #t)
         (send chat-text change-style copy-style time-end copy-end)
         
         (set! copy-button-regions
               (cons (list time-end copy-end msg-id content)
                     copy-button-regions))
         
         (define content-start (send chat-text last-position))
         (render-content-with-code-blocks content)
         (define content-end (send chat-text last-position))
         
         (when (eq? role 'tool)
           (define border-style (new style-delta%))
           (send chat-text insert "\n"))])
      
      (send chat-text lock #t)
      (scroll-to-bottom))
    
    (define copy-button-regions '())
    
    (define (render-content-with-code-blocks content)
      (define parts (regexp-split #rx"```" content))
      (define in-code? #f)
      (for ([part (in-list parts)])
        (cond
          [in-code?
           (define lines (string-split part "\n" #:trim? #f))
           (define lang (if (pair? lines) (string-trim (first lines)) ""))
           (define code-content
             (if (and (pair? lines) (not (string=? lang "")))
                 (string-join (rest lines) "\n")
                 part))
           (define code-start (send chat-text last-position))
           (send chat-text insert "\n")
           (send chat-text insert code-content)
           (when (not (string-suffix? code-content "\n"))
             (send chat-text insert "\n"))
           (define code-end (send chat-text last-position))
           (define code-style (new style-delta%))
           (send code-style set-delta-background code-bg)
           (send code-style set-family 'modern)
           (send chat-text change-style code-style code-start code-end)
           (set! in-code? #f)]
          [else
           (send chat-text insert part)
           (set! in-code? #t)])))
    
    (define/public (append-message role content [timestamp (current-seconds)])
      (set! message-counter (add1 message-counter))
      (define msg (chat-message role content timestamp message-counter))
      (set! messages (append messages (list msg)))
      (render-message msg))
    
    (define/public (append-streaming-chunk content)
      (send chat-text lock #f)
      (when (not streaming?)
        (set! streaming? #t)
        (set! streaming-start-pos (send chat-text last-position))
        (send chat-text insert "\n")
        (define icon (get-icon 'assistant))
        (define time-str (format-timestamp (current-seconds)))
        (send chat-text insert (format "~a Assistant  ~a\n" icon time-str))
        (define header-end (send chat-text last-position))
        (define header-style (new style-delta%))
        (send header-style set-weight-on 'bold)
        (send header-style set-delta-foreground (make-object color% 120 200 120))
        (send chat-text change-style header-style streaming-start-pos header-end)
        (set! streaming-start-pos (send chat-text last-position))
        (start-cursor-animation!))
      
      (when cursor-timer
        (remove-cursor!))
      
      (send chat-text insert content)
      (add-cursor!)
      (send chat-text lock #t)
      (scroll-to-bottom))
    
    (define (start-cursor-animation!)
      (set! cursor-timer
            (new timer%
                 [notify-callback
                  (λ ()
                    (set! cursor-visible? (not cursor-visible?))
                    (send chat-text lock #f)
                    (define pos (send chat-text last-position))
                    (when (> pos 0)
                      (define last-char (send chat-text get-text (sub1 pos) pos))
                      (cond
                        [(string=? last-char "▌")
                         (send chat-text delete (sub1 pos) pos)
                         (when cursor-visible?
                           (send chat-text insert "▌"))]
                        [cursor-visible?
                         (send chat-text insert "▌")]))
                    (send chat-text lock #t))]
                 [interval 500])))
    
    (define (add-cursor!)
      (when cursor-visible?
        (send chat-text insert "▌")))
    
    (define (remove-cursor!)
      (define pos (send chat-text last-position))
      (when (> pos 0)
        (define last-char (send chat-text get-text (sub1 pos) pos))
        (when (string=? last-char "▌")
          (send chat-text delete (sub1 pos) pos))))
    
    (define/public (finish-streaming)
      (when streaming?
        (when cursor-timer
          (send cursor-timer stop)
          (set! cursor-timer #f))
        (send chat-text lock #f)
        (remove-cursor!)
        (send chat-text lock #t)
        
        (define streamed-content
          (send chat-text get-text streaming-start-pos (send chat-text last-position)))
        (set! message-counter (add1 message-counter))
        (define msg (chat-message 'assistant streamed-content (current-seconds) message-counter))
        (set! messages (append messages (list msg)))
        
        (set! streaming? #f)
        (set! streaming-start-pos 0)))
    
    (define/public (clear-messages)
      (send chat-text lock #f)
      (send chat-text erase)
      (send chat-text lock #t)
      (set! messages '())
      (set! message-counter 0)
      (set! copy-button-regions '())
      (when streaming?
        (finish-streaming)))
    
    (define/public (scroll-to-bottom)
      (send chat-text scroll-to-position (send chat-text last-position)))
    
    (define/public (get-history)
      (for/list ([msg (in-list messages)])
        (cons (chat-message-role msg) (chat-message-content msg))))
    
    (define (handle-click x y)
      (define pos (send chat-text find-position x y))
      (for ([region (in-list copy-button-regions)])
        (match-define (list start end msg-id content) region)
        (when (and (>= pos start) (< pos end))
          (send the-clipboard set-clipboard-string content (current-seconds)))))
    
    (send chat-canvas set-canvas-background bg-color)))

(define (make-chat-widget parent #:theme [theme #f])
  (new chat-widget%
       [parent parent]
       [theme theme]))

(define (format-code-block code language)
  (format "```~a\n~a\n```" (or language "") code))
