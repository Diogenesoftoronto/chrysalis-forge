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

  (define last-break-time 0)

  (let loop ()
    (with-handlers ([exn:fail? (λ (e)
                                 (eprintf "[ACP FATAL] ~a~n" (exn-message e)))]
                    [exn:break? (λ (e)
                                  (define now (current-seconds))
                                  (if (< (- now last-break-time) 2)
                                      (begin
                                        (eprintf "[ACP] User break, shutting down.~n")
                                        (exit 0))
                                      (begin
                                        (eprintf "[ACP] ^C (Press Ctrl+C again to quit)~n")
                                        (set! last-break-time now)
                                        (loop))))])
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
                                   'modeState (hash 'currentMode mode
                                                    'availableModes supported-modes)))]

              ;; Set session mode
              ["session/set_mode"
               (eprintf "[ACP] Setting session mode~n")
               (define mode (hash-ref params 'mode "code"))
               (acp-respond! out id (hash 'currentMode mode))]

              ;; Handle prompt
              ["session/prompt"
               (eprintf "[ACP] Handling prompt~n")
               (define sid (hash-ref params 'sessionId "s1"))
               ;; Accept both 'prompt (legacy) and 'input (ACP spec) keys
               (define prompt-content
                 (cond
                   [(hash-has-key? params 'input) (hash-ref params 'input)]
                   [else (hash-ref params 'prompt "")]))
               ;; Handle both string and structured prompts
               (define prompt-text
                 (cond
                   [(string? prompt-content) prompt-content]
                   [(list? prompt-content)
                    (string-join
                     (for/list ([p prompt-content] #:when (equal? (hash-ref p 'type #f) "text"))
                       (hash-ref p 'text ""))
                     "\n")]
                   [(hash? prompt-content)
                    ;; Handle nested content array: { content: [{ type: "text", text: "..." }] }
                    (define content (hash-ref prompt-content 'content #f))
                    (cond
                      [(list? content)
                       (string-join
                        (for/list ([p content] #:when (equal? (hash-ref p 'type #f) "text"))
                          (hash-ref p 'text ""))
                        "\n")]
                      [(string? content) content]
                      [else (hash-ref prompt-content 'text "")])]
                   [else ""]))

               ;; Agent message emit callback - ACP spec compliant
               (define (agent-emit! t)
                 (acp-notify! out "session/update"
                              (hash 'sessionId sid
                                    'update (hash 'sessionUpdate "agent_message_chunk"
                                                  'content (hash 'type "text"
                                                                 'text t)))))

               ;; Tool call emit callback - ACP spec compliant
               (define (tool-emit! tool-event)
                 (define event-type (hash-ref tool-event 'event #f))
                 (define tool-call-id (hash-ref tool-event 'toolCallId #f))
                 (match event-type
                   ["start"
                    (acp-notify! out "session/update"
                                 (hash 'sessionId sid
                                       'update (hash 'sessionUpdate "tool_call"
                                                     'toolCallId tool-call-id
                                                     'title (hash-ref tool-event 'title "Tool")
                                                     'kind (hash-ref tool-event 'kind "other")
                                                     'status "pending"
                                                     'rawInput (hash-ref tool-event 'rawInput (hash)))))]
                   ["progress"
                    (acp-notify! out "session/update"
                                 (hash 'sessionId sid
                                       'update (hash 'sessionUpdate "tool_call_update"
                                                     'toolCallId tool-call-id
                                                     'status "in_progress")))]
                   ["finish"
                    (acp-notify! out "session/update"
                                 (hash 'sessionId sid
                                       'update (hash 'sessionUpdate "tool_call_update"
                                                     'toolCallId tool-call-id
                                                     'status (if (hash-ref tool-event 'error #f) "failed" "completed")
                                                     'content (list (hash 'type "content"
                                                                          'content (hash 'type "text"
                                                                                         'text (hash-ref tool-event 'output "")))))))]
                   [_ (void)]))

               ;; Run the turn with error handling
               (with-handlers ([exn:fail? (λ (e)
                                            (eprintf "[ACP] Turn error: ~a~n" (exn-message e))
                                            ;; Send error as agent message then complete turn
                                            (agent-emit! (format "Error: ~a" (exn-message e)))
                                            (acp-respond! out id (hash 'stopReason "end_turn")))])
                 (run-turn sid prompt-text agent-emit! tool-emit! (λ () #f))
                 ;; Send turn complete response - ACP spec uses snake_case
                 (acp-respond! out id (hash 'stopReason "end_turn")))]

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
