#lang racket/base

(provide mcp-client?
         mcp-connect
         mcp-disconnect
         mcp-list-tools
         mcp-call-tool
         mcp-client       ; Constructor
         mcp-client-name
         mcp-client-tools)

(require json
         racket/system
         racket/port
         racket/string
         racket/match)

(struct mcp-client (name process stdin stdout stderr tools) #:mutable)

(define (json-rpc-request method params [id #f])
  (make-hash (list (cons 'jsonrpc "2.0")
                   (cons 'method method)
                   (cons 'params params)
                   (cons 'id (or id (current-milliseconds))))))

(define (read-json-rpc input-port)
  (read-json input-port))

(define (write-json-rpc output-port data)
  (write-json data output-port)
  (newline output-port)
  (flush-output output-port))

(define (mcp-connect name command args)
  (define-values (sp stdout stdin stderr)
    (apply subprocess #f #f #f (find-executable-path command) args))
  
  (define client (mcp-client name sp stdin stdout stderr '()))
  
  ;; Initialize
  (define init-req
    (json-rpc-request "initialize"
                      (hash 'protocolVersion "2024-11-05"
                            'capabilities (hash 'roots (hash 'listChanged #t))
                            'clientInfo (hash 'name "chrysalis-forge-agent"
                                              'version "0.1.0"))
                      1))
  
  (write-json-rpc stdin init-req)
  
  ;; Wait for initialize response
  (define init-resp (read-json-rpc stdout))
  
  (when (hash-has-key? init-resp 'error)
    (error 'mcp-connect "MCP Initialization failed: ~a" (hash-ref init-resp 'error)))

  ;; Send initialized notification
  (write-json-rpc stdin (make-hash (list (cons 'jsonrpc "2.0")
                                         (cons 'method "notifications/initialized"))))
  
  ;; List tools
  (define tools (mcp-refresh-tools client))
  (set-mcp-client-tools! client tools)
  
  client)

(define (mcp-disconnect client)
  (close-input-port (mcp-client-stdout client))
  (close-output-port (mcp-client-stdin client))
  (close-input-port (mcp-client-stderr client))
  (subprocess-kill (mcp-client-process client) #t))

(define (mcp-refresh-tools client)
  (define req (json-rpc-request "tools/list" (hash) (current-milliseconds)))
  (write-json-rpc (mcp-client-stdin client) req)
  
  (define resp (read-json-rpc (mcp-client-stdout client)))
  
  (cond
    [(hash-has-key? resp 'error)
     (error 'mcp-list-tools "Failed to list tools: ~a" (hash-ref resp 'error))]
    [(hash-has-key? resp 'result)
     (define result (hash-ref resp 'result))
     (hash-ref result 'tools '())]
    [else '()]))

(define (mcp-list-tools client)
  (mcp-client-tools client))

(define (mcp-call-tool client tool-name args)
  (define req (json-rpc-request "tools/call"
                                (hash 'name tool-name
                                      'arguments args)
                                (current-milliseconds)))
  (write-json-rpc (mcp-client-stdin client) req)
  
  (define resp (read-json-rpc (mcp-client-stdout client)))
  
  (cond
    [(hash-has-key? resp 'error)
     (format "MCP Tool Error: ~a" (hash-ref (hash-ref resp 'error) 'message))]
    [(hash-has-key? resp 'result)
     (define result (hash-ref resp 'result))
     ;; Result usually has 'content' list
     (define content (hash-ref result 'content '()))
     (string-join (map (λ (c) (hash-ref c 'text "")) content) "\n")]
    [else "No output returned."]))
