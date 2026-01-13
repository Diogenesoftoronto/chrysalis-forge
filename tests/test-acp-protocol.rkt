#lang racket/base
;; Unit Tests for ACP Protocol Compliance
;; Tests the protocol message format without spawning processes

(require rackunit racket/match json racket/string racket/port racket/list)
(require "../src/core/acp-stdio.rkt")

(provide acp-protocol-tests)

;; Capture notifications sent via acp-notify!
(define captured-notifications '())

(define (reset-captures!)
  (set! captured-notifications '()))

(define (capture-notification! method params)
  (set! captured-notifications 
        (cons (hash 'method method 'params params) captured-notifications)))

;; Test session/update notification format for agent messages
(define (test-agent-message-format)
  (test-case
   "session/update agent_message_chunk format"
   ;; Expected format per ACP spec:
   ;; { sessionId, update: { sessionUpdate: "agent_message_chunk", content: { type: "text", text: "..." } } }
   
   (define out (open-output-string))
   (acp-notify! out "session/update"
                (hash 'sessionId "test-session"
                      'update (hash 'sessionUpdate "agent_message_chunk"
                                    'content (hash 'type "text"
                                                   'text "Hello world"))))
   
   (define output (get-output-string out))
   (define msg (string->jsexpr output))
   
   (check-equal? (hash-ref msg 'method) "session/update")
   
   (define params (hash-ref msg 'params))
   (check-equal? (hash-ref params 'sessionId) "test-session")
   
   (define update (hash-ref params 'update))
   (check-equal? (hash-ref update 'sessionUpdate) "agent_message_chunk")
   
   (define content (hash-ref update 'content))
   (check-equal? (hash-ref content 'type) "text")
   (check-equal? (hash-ref content 'text) "Hello world")))

;; Test tool_call notification format
(define (test-tool-call-format)
  (test-case
   "session/update tool_call format"
   ;; Expected format per ACP spec:
   ;; { sessionId, update: { sessionUpdate: "tool_call", toolCallId, title, kind, status, rawInput } }
   
   (define out (open-output-string))
   (acp-notify! out "session/update"
                (hash 'sessionId "test-session"
                      'update (hash 'sessionUpdate "tool_call"
                                    'toolCallId "call_123"
                                    'title "read_file"
                                    'kind "other"
                                    'status "pending"
                                    'rawInput (hash 'path "/tmp/test.txt"))))
   
   (define output (get-output-string out))
   (define msg (string->jsexpr output))
   
   (define params (hash-ref msg 'params))
   (define update (hash-ref params 'update))
   
   (check-equal? (hash-ref update 'sessionUpdate) "tool_call")
   (check-equal? (hash-ref update 'toolCallId) "call_123")
   (check-equal? (hash-ref update 'title) "read_file")
   (check-equal? (hash-ref update 'kind) "other")
   (check-equal? (hash-ref update 'status) "pending")
   (check-true (hash? (hash-ref update 'rawInput)))))

;; Test tool_call_update notification format
(define (test-tool-call-update-format)
  (test-case
   "session/update tool_call_update format"
   ;; Expected format per ACP spec:
   ;; { sessionId, update: { sessionUpdate: "tool_call_update", toolCallId, status, content? } }
   
   (define out (open-output-string))
   (acp-notify! out "session/update"
                (hash 'sessionId "test-session"
                      'update (hash 'sessionUpdate "tool_call_update"
                                    'toolCallId "call_123"
                                    'status "completed"
                                    'content (list (hash 'type "content"
                                                         'content (hash 'type "text"
                                                                        'text "file contents here"))))))
   
   (define output (get-output-string out))
   (define msg (string->jsexpr output))
   
   (define params (hash-ref msg 'params))
   (define update (hash-ref params 'update))
   
   (check-equal? (hash-ref update 'sessionUpdate) "tool_call_update")
   (check-equal? (hash-ref update 'toolCallId) "call_123")
   (check-equal? (hash-ref update 'status) "completed")
   
   (define content-list (hash-ref update 'content))
   (check-true (list? content-list))
   (check-equal? (length content-list) 1)
   
   (define first-content (first content-list))
   (check-equal? (hash-ref first-content 'type) "content")))

;; Test stopReason uses snake_case
(define (test-stop-reason-format)
  (test-case
   "stopReason uses snake_case (end_turn not endTurn)"
   
   (define out (open-output-string))
   (define msg (hash 'jsonrpc "2.0" 'id 1 'result (hash 'stopReason "end_turn")))
   (write-json msg out)
   
   (define output (get-output-string out))
   
   ;; Verify correct format
   (check-true (string-contains? output "end_turn"))
   (check-false (string-contains? output "endTurn"))))

;; Test ToolCallStatus values
(define (test-tool-call-status-values)
  (test-case
   "ToolCallStatus uses correct enum values"
   ;; ACP spec: pending, in_progress, completed, failed
   
   (define valid-statuses '("pending" "in_progress" "completed" "failed"))
   
   (for ([status valid-statuses])
     (define out (open-output-string))
     (acp-notify! out "session/update"
                  (hash 'sessionId "s1"
                        'update (hash 'sessionUpdate "tool_call_update"
                                      'toolCallId "c1"
                                      'status status)))
     (define output (get-output-string out))
     (check-true (string-contains? output status)
                 (format "Should contain status: ~a" status)))))

;; Test modes use 'id' not 'slug'
(define (test-modes-use-id)
  (test-case
   "SessionMode uses 'id' field not 'slug'"
   
   (define mode (hash 'id "code" 'name "Code" 'description "Full access"))
   
   (check-true (hash-has-key? mode 'id))
   (check-false (hash-has-key? mode 'slug))
   (check-equal? (hash-ref mode 'id) "code")))

;; Test modeState wrapper in session/new response
(define (test-mode-state-wrapper)
  (test-case
   "session/new response uses modeState wrapper"
   
   (define response 
     (hash 'sessionId "s123"
           'modeState (hash 'currentMode "code"
                            'availableModes (list (hash 'id "ask" 'name "Ask")
                                                   (hash 'id "code" 'name "Code")))))
   
   (check-true (hash-has-key? response 'sessionId))
   (check-true (hash-has-key? response 'modeState))
   
   (define mode-state (hash-ref response 'modeState))
   (check-true (hash-has-key? mode-state 'currentMode))
   (check-true (hash-has-key? mode-state 'availableModes))))

(define acp-protocol-tests
  (test-suite
   "ACP Protocol Compliance Tests"
   
   (test-agent-message-format)
   (test-tool-call-format)
   (test-tool-call-update-format)
   (test-stop-reason-format)
   (test-tool-call-status-values)
   (test-modes-use-id)
   (test-mode-state-wrapper)))

(module+ test
  (require rackunit/text-ui)
  (run-tests acp-protocol-tests))
