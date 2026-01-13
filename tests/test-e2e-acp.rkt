#lang racket/base
;; End-to-End Tests for ACP Protocol and Logging
(require rackunit racket/system racket/port racket/string json racket/list)

(provide e2e-tests)

(define AGENTD-PATH "/home/diogenes/Projects/chrysalis-forge/main.rkt")

;; Helper to run agentd with input and capture output
(define (run-acp-test input-lines)
  (define input-str (string-join input-lines "\n"))
  (define cmd (format "echo '~a' | timeout 5 racket ~a --acp 2>&1 || true" 
                      input-str AGENTD-PATH))
  (define output (with-output-to-string 
                   (λ () (system cmd))))
  output)

;; Extract JSON response from output
(define (extract-json-response output)
  (define lines (string-split output "\n"))
  (for/first ([line lines]
              #:when (and (> (string-length line) 0)
                          (char=? (string-ref line 0) #\{)
                          (regexp-match? #rx"\"jsonrpc\"" line)))
    (string->jsexpr line)))

;; Helper to extract all JSON responses from output
(define (extract-all-json-responses output)
  (define lines (string-split output "\n"))
  (filter-map 
   (λ (line)
     (and (> (string-length line) 0)
          (char=? (string-ref line 0) #\{)
          (regexp-match? #rx"\"jsonrpc\"" line)
          (with-handlers ([exn:fail? (λ (_) #f)])
            (string->jsexpr line))))
   lines))

;; Helper to find response by id
(define (find-response-by-id responses id)
  (for/first ([r responses] #:when (equal? (hash-ref r 'id #f) id)) r))

;; Helper to find notification by method
(define (find-notification responses method)
  (for/first ([r responses] 
              #:when (and (not (hash-has-key? r 'id))
                          (equal? (hash-ref r 'method #f) method))) 
    r))

(define e2e-tests
  (test-suite
   "End-to-End ACP Tests"
   
   (test-case
    "ACP Initialize Response"
    (define output (run-acp-test 
                    '("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-01-20\"}}")))
    
    ;; Check banner appears
    (check-true (string-contains? output "Chrysalis Forge ACP Server"))
    (check-true (string-contains? output "Transport: stdio"))
    
    ;; Check ACP logging
    (check-true (string-contains? output "[ACP] Server started"))
    (check-true (string-contains? output "[ACP IN]"))
    (check-true (string-contains? output "[ACP] Initialize request"))
    (check-true (string-contains? output "[ACP OUT] Response id=1"))
    
    ;; Parse and verify JSON response
    (define resp (extract-json-response output))
    (check-not-false resp)
    (check-equal? (hash-ref resp 'id) 1)
    (check-true (hash-has-key? (hash-ref resp 'result) 'protocolVersion))
    (check-true (hash-has-key? (hash-ref resp 'result) 'agentInfo))
    (check-true (hash-has-key? (hash-ref resp 'result) 'agentCapabilities)))
   
   (test-case
    "ACP Initialize - Modes use 'id' not 'slug'"
    (define output (run-acp-test 
                    '("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-01-20\"}}")))
    
    (define resp (extract-json-response output))
    (check-not-false resp)
    
    ;; Verify modes have 'id' field (ACP spec), not 'slug'
    (define caps (hash-ref (hash-ref resp 'result) 'agentCapabilities))
    (define session-caps (hash-ref caps 'sessionCapabilities))
    (define modes (hash-ref session-caps 'modes))
    
    (check-true (> (length modes) 0) "Should have at least one mode")
    (define first-mode (first modes))
    (check-true (hash-has-key? first-mode 'id) "Mode should have 'id' field")
    (check-false (hash-has-key? first-mode 'slug) "Mode should NOT have 'slug' field")
    (check-true (hash-has-key? first-mode 'name) "Mode should have 'name' field"))
   
   (test-case
    "ACP Session New - modeState wrapper"
    (define output (run-acp-test 
                    '("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-01-20\"}}"
                      "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"session/new\",\"params\":{\"mode\":\"code\"}}")))
    
    ;; Check session creation logged
    (check-true (string-contains? output "[ACP] Creating new session"))
    
    ;; Find session/new response
    (define responses (extract-all-json-responses output))
    (define session-resp (find-response-by-id responses 2))
    
    (check-not-false session-resp "Should have response for id=2")
    (define result (hash-ref session-resp 'result))
    
    ;; Verify structure: { sessionId, modeState: { currentMode, availableModes } }
    (check-true (hash-has-key? result 'sessionId) "Should have sessionId")
    (check-true (hash-has-key? result 'modeState) "Should have modeState wrapper")
    
    (define mode-state (hash-ref result 'modeState))
    (check-true (hash-has-key? mode-state 'currentMode) "modeState should have currentMode")
    (check-true (hash-has-key? mode-state 'availableModes) "modeState should have availableModes")
    (check-equal? (hash-ref mode-state 'currentMode) "code"))
   
   (test-case
    "ACP session/set_mode - snake_case method name"
    (define output (run-acp-test 
                    '("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}"
                      "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"session/new\",\"params\":{\"mode\":\"code\"}}"
                      "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"session/set_mode\",\"params\":{\"mode\":\"ask\"}}")))
    
    ;; Should not log as unknown method
    (check-false (string-contains? output "[ACP] Unknown method: session/set_mode"))
    (check-true (string-contains? output "[ACP] Setting session mode"))
    
    ;; Find response
    (define responses (extract-all-json-responses output))
    (define resp (find-response-by-id responses 3))
    (check-not-false resp "Should have response for session/set_mode")
    (check-equal? (hash-ref (hash-ref resp 'result) 'currentMode) "ask"))
   
   (test-case
    "ACP Unknown Method Error"
    (define output (run-acp-test 
                    '("{\"jsonrpc\":\"2.0\",\"id\":99,\"method\":\"unknown/method\",\"params\":{}}")))
    
    ;; Check error logged
    (check-true (string-contains? output "[ACP] Unknown method: unknown/method"))
    (check-true (string-contains? output "[ACP ERR]"))
    
    ;; Check error response
    (define responses (extract-all-json-responses output))
    (define err-resp (find-response-by-id responses 99))
    
    (check-not-false err-resp)
    (check-true (hash-has-key? err-resp 'error))
    (check-equal? (hash-ref (hash-ref err-resp 'error) 'code) -32601))))

(module+ test
  (require rackunit/text-ui)
  (run-tests e2e-tests))
