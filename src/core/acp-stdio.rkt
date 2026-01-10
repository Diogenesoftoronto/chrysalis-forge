#lang racket/base
(provide acp-serve acp-notify!)
(require json racket/match racket/port racket/string)

;; ACP Protocol Version
(define ACP-VERSION "2025-01-20")

(define (acp-notify! out method params)
  (define msg (hash 'jsonrpc "2.0" 'method method 'params params))
  (write-json msg out) 
  (newline out) 
  (flush-output out)
  (eprintf "[ACP OUT] Notification: ~a~n" method))

(define (acp-respond! out id result)
  (define msg (hash 'jsonrpc "2.0" 'id id 'result result))
  (write-json msg out)
  (newline out)
  (flush-output out)
  (eprintf "[ACP OUT] Response id=~a~n" id))

(define (acp-error! out id code message)
  (define msg (hash 'jsonrpc "2.0" 'id id 'error (hash 'code code 'message message)))
  (write-json msg out)
  (newline out)
  (flush-output out)
  (eprintf "[ACP ERR] ~a: ~a~n" code message))

(define (acp-serve #:modes supported-modes #:on-new-session on-new-session #:run-turn run-turn)
  (define in (current-input-port)) 
  (define out (current-output-port))
  (eprintf "[ACP] Server started, waiting for messages...~n")
  
  (let loop ()
    (with-handlers ([exn:fail? (λ (e) 
                                 (eprintf "[ACP FATAL] ~a~n" (exn-message e)))])
      (define line (read-line in))
      (unless (eof-object? line)
        (when (> (string-length line) 0)
          (eprintf "[ACP IN] ~a~n" (if (> (string-length line) 200) 
                                        (string-append (substring line 0 200) "...") 
                                        line))
          (with-handlers ([exn:fail? (λ (e)
                                       (eprintf "[ACP PARSE ERROR] ~a~n" (exn-message e)))])
            (define msg (string->jsexpr line))
            (define id (hash-ref msg 'id #f))
            (define method (hash-ref msg 'method #f))
            (define params (hash-ref msg 'params (hash)))
            
            (match method
              ;; Initialize - required first message
              ["initialize" 
               (eprintf "[ACP] Initialize request~n")
               (acp-respond! out id 
                             (hash 'protocolVersion ACP-VERSION
                                   'agentInfo (hash 'name "chrysalis-forge"
                                                    'version "1.0.0"
                                                    'title "Chrysalis Forge")
                                   'agentCapabilities 
                                   (hash 'loadSession #f
                                         'promptCapabilities (hash 'image #t 
                                                                    'audio #f 
                                                                    'embeddedContext #t)
                                         'sessionCapabilities (hash 'modes supported-modes))))]
              
              ;; Initialized notification (no response needed)
              ["initialized"
               (eprintf "[ACP] Client confirmed initialization~n")]
              
              ;; Shutdown request
              ["shutdown"
               (eprintf "[ACP] Shutdown requested~n")
               (when id (acp-respond! out id (hash)))]
              
              ;; Exit notification
              ["exit"
               (eprintf "[ACP] Exit~n")
               (exit 0)]
              
              ;; Create new session
              ["session/new" 
               (eprintf "[ACP] Creating new session~n")
               (define mode (hash-ref params 'mode "code"))
               (define sid (format "s~a" (random 100000)))
               (on-new-session sid mode)
               (acp-respond! out id 
                             (hash 'sessionId sid
                                   'availableModes supported-modes
                                   'currentMode mode))]
              
              ;; Set session mode
              ["session/setMode"
               (eprintf "[ACP] Setting session mode~n")
               (define mode (hash-ref params 'mode "code"))
               (acp-respond! out id (hash 'currentMode mode))]
              
              ;; Handle prompt
              ["session/prompt" 
               (eprintf "[ACP] Handling prompt~n")
               (define sid (hash-ref params 'sessionId "s1"))
               (define prompt-content (hash-ref params 'prompt ""))
               ;; Handle both string and structured prompts
               (define prompt-text 
                 (cond
                   [(string? prompt-content) prompt-content]
                   [(list? prompt-content) 
                    (string-join 
                     (for/list ([p prompt-content] #:when (equal? (hash-ref p 'type #f) "text"))
                       (hash-ref p 'text ""))
                     "\n")]
                   [(hash? prompt-content) (hash-ref prompt-content 'text "")]
                   [else ""]))
               
               ;; Run the turn
               (run-turn sid prompt-text 
                         (λ (t) 
                           (acp-notify! out "session/update" 
                                        (hash 'sessionId sid
                                              'update (hash 'type "agentMessage"
                                                            'message (hash 'type "text"
                                                                           'text t)))))
                         (λ (_) (void)) 
                         (λ () #f))
               
               ;; Send turn complete response
               (acp-respond! out id (hash 'stopReason "endTurn"))]
              
              ;; Cancel notification
              ["session/cancel"
               (eprintf "[ACP] Cancel requested for session~n")]
              
              ;; Unknown method
              [#f 
               (eprintf "[ACP] No method in message~n")]
              
              [other 
               (eprintf "[ACP] Unknown method: ~a~n" other)
               (when id 
                 (acp-error! out id -32601 (format "Method not found: ~a" other)))])))
        (loop)))))