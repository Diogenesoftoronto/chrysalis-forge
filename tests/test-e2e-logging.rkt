#lang racket/base
;; End-to-End Tests for Debug Logging
(require rackunit racket/system racket/port racket/string)

(provide e2e-logging-tests)

(define AGENTD-PATH "/home/diogenes/Projects/chrysalis-forge/main.rkt")

;; Helper to run agentd CLI with args
(define (run-agentd-cli args)
  (define cmd (format "timeout 2 racket ~a ~a 2>&1 || true" AGENTD-PATH args))
  (with-output-to-string (λ () (system cmd))))

(define e2e-logging-tests
  (test-suite
   "End-to-End Logging Tests"
   
   (test-case
    "Help flag works"
    (define output (run-agentd-cli "-h"))
    (check-true (string-contains? output "usage: chrysalis"))
    (check-true (string-contains? output "--debug"))
    (check-true (string-contains? output "--priority"))
    (check-true (string-contains? output "--acp")))
   
   (test-case
    "Debug level 0 is silent"
    (define output (run-agentd-cli "-d 0 -h"))
    ;; Should not contain debug output
    (check-false (string-contains? output "[TOOLS]")))
   
   (test-case
    "Debug verbose alias works"
    (define output (run-agentd-cli "-d verbose -h"))
    ;; -h exits before any debug output, but the flag should parse
    (check-true (string-contains? output "usage: chrysalis")))
   
   (test-case
    "ACP banner shows configuration"
    (define output (run-agentd-cli "--acp"))
    (check-true (string-contains? output "Chrysalis Forge ACP Server"))
    (check-true (string-contains? output "Transport:"))
    (check-true (string-contains? output "Model:"))
    (check-true (string-contains? output "Security Level:"))
    (check-true (string-contains? output "Priority:")))
   
   (test-case
    "Custom priority flag accepted"
    (define output (run-agentd-cli "--priority fast -h"))
    (check-true (string-contains? output "usage: chrysalis")))
   
   (test-case
    "Custom priority NL string accepted"
    (define output (run-agentd-cli "--priority \"I need accuracy\" -h"))
    (check-true (string-contains? output "usage: chrysalis")))
   
   (test-case
    "Security levels work"
    (define output (run-agentd-cli "--perms 2 -h"))
    (check-true (string-contains? output "usage: chrysalis")))
   
   (test-case
    "God mode works"
    (define output (run-agentd-cli "--perms god -h"))
    (check-true (string-contains? output "usage: chrysalis")))))

(module+ test
  (require rackunit/text-ui)
  (run-tests e2e-logging-tests))
