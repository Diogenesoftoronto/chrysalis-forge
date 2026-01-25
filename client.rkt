#lang racket/base
;; Chrysalis Client - Full-screen TUI for connecting to Chrysalis services
;; This client provides an animated, interactive terminal UI

(require racket/cmdline
         racket/string
         "src/service/client.rkt"
         "src/tui/client.rkt")

;; ============================================================================
;; Client Entry Point
;; ============================================================================

(define url-param (make-parameter "http://127.0.0.1:8080"))
(define api-key-param (make-parameter #f))
(define repl-mode-param (make-parameter #f))

(define (main)
  (command-line
   #:program "chrysalis-client"
   #:usage-help "Connect to a running Chrysalis Forge service"
   #:once-each
   [("--url" "-u") url "Service URL (default: http://127.0.0.1:8080)"
                   (url-param url)]
   [("--api-key" "-k") key "API key or JWT token for authentication"
                       (api-key-param key)]
   [("--repl") "Use legacy REPL mode instead of TUI"
               (repl-mode-param #t)]
   #:args ()
   (if (repl-mode-param)
       ;; Legacy REPL mode
       (client-repl (url-param) #:api-key (api-key-param))
       ;; New TUI mode
       (start-tui-client (url-param) #:api-key (api-key-param)))))

;; Run main when executed directly
(module+ main
  (main))
