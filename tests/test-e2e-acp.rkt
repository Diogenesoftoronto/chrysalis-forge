#lang racket/base
;; End-to-End Tests for ACP Protocol and Logging
(require rackunit racket/system racket/port racket/string json)

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
    "ACP Session New Response"
    (define output (run-acp-test 
                    '("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-01-20\"}}"
                      "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"session/new\",\"params\":{\"mode\":\"code\"}}")))
    
    ;; Check session creation logged
    (check-true (string-contains? output "[ACP] Creating new session"))
    
    ;; Find session/new response
    (define lines (string-split output "\n"))
    (define session-resp 
      (for/first ([line lines]
                  #:when (and (string-contains? line "\"id\":2")
                              (string-contains? line "sessionId")))
        (string->jsexpr line)))
    
    (check-not-false session-resp)
    (check-true (hash-has-key? (hash-ref session-resp 'result) 'sessionId))
    (check-true (hash-has-key? (hash-ref session-resp 'result) 'availableModes)))
   
   (test-case
    "ACP Unknown Method Error"
    (define output (run-acp-test 
                    '("{\"jsonrpc\":\"2.0\",\"id\":99,\"method\":\"unknown/method\",\"params\":{}}")))
    
    ;; Check error logged
    (check-true (string-contains? output "[ACP] Unknown method: unknown/method"))
    (check-true (string-contains? output "[ACP ERR]"))
    
    ;; Check error response
    (define lines (string-split output "\n"))
    (define err-resp 
      (for/first ([line lines]
                  #:when (and (string-contains? line "\"error\"")
                              (string-contains? line "-32601")))
        (string->jsexpr line)))
    
    (check-not-false err-resp)
    (check-equal? (hash-ref err-resp 'id) 99)
    (check-equal? (hash-ref (hash-ref err-resp 'error) 'code) -32601))))

(module+ test
  (require rackunit/text-ui)
  (run-tests e2e-tests))
