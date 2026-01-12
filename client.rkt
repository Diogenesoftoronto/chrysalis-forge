#lang racket/base
;; Chrysalis Client - Lightweight CLI for connecting to Chrysalis services
;; This is a minimal client without the full agent tooling

(require racket/cmdline
         racket/string
         "src/service/client.rkt")

;; ============================================================================
;; Client Entry Point
;; ============================================================================

(define url-param (make-parameter "http://127.0.0.1:8080"))
(define api-key-param (make-parameter #f))

(define (main)
  (command-line
   #:program "chrysalis-client"
   #:usage-help "Connect to a running Chrysalis Forge service"
   #:once-each
   [("--url" "-u") url "Service URL (default: http://127.0.0.1:8080)" 
    (url-param url)]
   [("--api-key" "-k") key "API key or JWT token for authentication" 
    (api-key-param key)]
   #:args ()
   (client-repl (url-param) #:api-key (api-key-param))))

;; Run main when executed directly
(module+ main
  (main))
