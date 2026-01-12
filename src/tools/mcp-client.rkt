#lang racket/base

(provide mcp-client?
         mcp-connect
         mcp-disconnect
         mcp-list-tools
         mcp-call-tool
         mcp-client       ; Constructor
         mcp-client-name
         mcp-client-tools
         ;; Session metrics
         mcp-get-session-stats
         mcp-reset-session-stats!)

(require json
         racket/system
         racket/port
         racket/string
         racket/match)

(struct mcp-client (name process stdin stdout stderr tools) #:mutable)

;; ============================================================================
;; MCP Session Metrics - Track connection and tool call statistics
;; ============================================================================

(define mcp-session-stats
  (box (hash 'connections 0
             'connection_failures 0
             'tool_calls 0
             'tool_success 0
             'tool_failures 0
             'clients (hash))))

(define (mcp-record-connection! name ok?)
  (define stats (unbox mcp-session-stats))
  (define new-stats
    (hash-set (if ok?
                  (hash-set stats 'connections (add1 (hash-ref stats 'connections)))
                  (hash-set stats 'connection_failures (add1 (hash-ref stats 'connection_failures))))
              'clients
              (if ok?
                  (hash-set (hash-ref stats 'clients) name (hash 'calls 0 'success 0 'failures 0))
                  (hash-ref stats 'clients))))
  (set-box! mcp-session-stats new-stats))

(define (mcp-record-tool-call! client-name ok?)
  (define stats (unbox mcp-session-stats))
  (define new-calls (add1 (hash-ref stats 'tool_calls)))
  (define new-success (if ok? (add1 (hash-ref stats 'tool_success)) (hash-ref stats 'tool_success)))
  (define new-failures (if ok? (hash-ref stats 'tool_failures) (add1 (hash-ref stats 'tool_failures))))
  (define clients (hash-ref stats 'clients))
  (define client-stats (hash-ref clients client-name (hash 'calls 0 'success 0 'failures 0)))
  (define new-client-stats
    (hash 'calls (add1 (hash-ref client-stats 'calls))
          'success (if ok? (add1 (hash-ref client-stats 'success)) (hash-ref client-stats 'success))
          'failures (if ok? (hash-ref client-stats 'failures) (add1 (hash-ref client-stats 'failures)))))
  (set-box! mcp-session-stats
            (hash 'connections (hash-ref stats 'connections)
                  'connection_failures (hash-ref stats 'connection_failures)
                  'tool_calls new-calls
                  'tool_success new-success
                  'tool_failures new-failures
                  'clients (hash-set clients client-name new-client-stats))))

(define (mcp-get-session-stats)
  (unbox mcp-session-stats))

(define (mcp-reset-session-stats!)
  (set-box! mcp-session-stats
            (hash 'connections 0
                  'connection_failures 0
                  'tool_calls 0
                  'tool_success 0
                  'tool_failures 0
                  'clients (hash))))

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
  (with-handlers ([exn:fail?
                   (λ (e)
                     (mcp-record-connection! name #f)
                     (raise e))])
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
      (mcp-record-connection! name #f)
      (error 'mcp-connect "MCP Initialization failed: ~a" (hash-ref init-resp 'error)))

    ;; Send initialized notification
    (write-json-rpc stdin (make-hash (list (cons 'jsonrpc "2.0")
                                           (cons 'method "notifications/initialized"))))
    
    ;; List tools
    (define tools (mcp-refresh-tools client))
    (set-mcp-client-tools! client tools)
    
    ;; Record successful connection
    (mcp-record-connection! name #t)
    
    client))

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
  (define client-name (mcp-client-name client))
  (define req (json-rpc-request "tools/call"
                                (hash 'name tool-name
                                      'arguments args)
                                (current-milliseconds)))
  (write-json-rpc (mcp-client-stdin client) req)
  
  (define resp (read-json-rpc (mcp-client-stdout client)))
  
  (cond
    [(hash-has-key? resp 'error)
     (mcp-record-tool-call! client-name #f)
     (format "MCP Tool Error: ~a" (hash-ref (hash-ref resp 'error) 'message))]
    [(hash-has-key? resp 'result)
     (mcp-record-tool-call! client-name #t)
     (define result (hash-ref resp 'result))
     ;; Result usually has 'content' list
     (define content (hash-ref result 'content '()))
     (string-join (map (λ (c) (hash-ref c 'text "")) content) "\n")]
    [else
     (mcp-record-tool-call! client-name #f)
     "No output returned."]))
