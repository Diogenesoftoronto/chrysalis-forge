#lang racket/base
(provide lsp-start! lsp-stop! lsp-get-diagnostics lsp-hover lsp-definition
         lsp-list-servers lsp-status make-lsp-tools execute-lsp-tool)
(require racket/port racket/string racket/list racket/match racket/format racket/file
         json racket/system racket/path "../utils/debug.rkt")

;; ============================================================================
;; LSP CLIENT - Language Server Protocol integration
;; ============================================================================

;; Active LSP servers: language -> (hash 'process 'in 'out 'err 'request-id 'pending)
(define lsp-servers (make-hash))

;; Message ID counter
(define (next-request-id! lang)
  (define server (hash-ref lsp-servers lang #f))
  (when server
    (define id (add1 (hash-ref server 'request-id 0)))
    (hash-set! lsp-servers lang (hash-set server 'request-id id))
    id))

;; Known language servers
(define LSP-COMMANDS
  (hash
   "racket" '("racket" "-l" "racket-langserver")
   "python" '("pylsp")
   "typescript" '("typescript-language-server" "--stdio")
   "javascript" '("typescript-language-server" "--stdio")
   "rust" '("rust-analyzer")
   "go" '("gopls")
   "c" '("clangd")
   "cpp" '("clangd")))

;; File extension to language mapping
(define (path->language path)
  (define ext (path-get-extension (string->path path)))
  (match (and ext (bytes->string/utf-8 ext))
    [".rkt" "racket"] [".scm" "racket"]
    [".py" "python"]
    [".ts" "typescript"] [".tsx" "typescript"]
    [".js" "javascript"] [".jsx" "javascript"]
    [".rs" "rust"]
    [".go" "go"]
    [".c" "c"] [".h" "c"]
    [".cpp" "cpp"] [".hpp" "cpp"] [".cc" "cpp"]
    [_ #f]))

;; ============================================================================
;; LSP MESSAGE ENCODING/DECODING
;; ============================================================================

(define (lsp-encode msg)
  (define json-str (jsexpr->string msg))
  (define len (string-utf-8-length json-str))
  (format "Content-Length: ~a\r\n\r\n~a" len json-str))

(define (lsp-read-message in)
  (with-handlers ([exn:fail? (λ (e) #f)])
    ;; Read headers
    (define headers (make-hash))
    (let loop ()
      (define line (read-line in 'return-linefeed))
      (cond
        [(or (eof-object? line) (string=? line "")) (void)]
        [else
         (define parts (string-split line ": "))
         (when (= (length parts) 2)
           (hash-set! headers (first parts) (second parts)))
         (loop)]))
    ;; Read body
    (define len-str (hash-ref headers "Content-Length" #f))
    (when len-str
      (define len (string->number len-str))
      (define body (read-string len in))
      (string->jsexpr body))))

;; ============================================================================
;; LSP PROTOCOL
;; ============================================================================

(define (lsp-send! lang method params #:id [id #f])
  (define server (hash-ref lsp-servers lang #f))
  (unless server
    (error 'lsp-send! "No LSP server for language: ~a" lang))
  (define out (hash-ref server 'out))
  (define msg
    (if id
        (hash 'jsonrpc "2.0" 'id id 'method method 'params params)
        (hash 'jsonrpc "2.0" 'method method 'params params)))
  (display (lsp-encode msg) out)
  (flush-output out)
  (log-debug 2 'lsp "Sent: ~a ~a" method (if id (format "(id=~a)" id) "(notification)")))

(define (lsp-receive! lang #:timeout [timeout 5])
  (define server (hash-ref lsp-servers lang #f))
  (unless server #f)
  (define in (hash-ref server 'in))
  ;; Simple blocking read with timeout via sync
  (define ready (sync/timeout timeout in))
  (if ready
      (lsp-read-message in)
      #f))

;; ============================================================================
;; LSP LIFECYCLE
;; ============================================================================

(define (lsp-start! lang #:root-path [root-path (current-directory)])
  (define cmd-args (hash-ref LSP-COMMANDS lang #f))
  (unless cmd-args
    (error 'lsp-start! "Unknown language: ~a. Known: ~a" lang (hash-keys LSP-COMMANDS)))
  
  (define exe (find-executable-path (first cmd-args)))
  (unless exe
    (error 'lsp-start! "LSP server not found: ~a" (first cmd-args)))
  
  (log-debug 1 'lsp "Starting LSP server for ~a: ~a" lang cmd-args)
  
  (define-values (proc stdout stdin stderr)
    (apply subprocess #f #f #f exe (rest cmd-args)))
  
  (hash-set! lsp-servers lang
             (hash 'process proc 'in stdout 'out stdin 'err stderr 'request-id 0))
  
  ;; Send initialize
  (define init-id (next-request-id! lang))
  (lsp-send! lang "initialize"
             (hash 'processId (getpid)
                   'rootPath (path->string root-path)
                   'rootUri (format "file://~a" (path->string root-path))
                   'capabilities (hash
                                  'textDocument (hash
                                                 'hover (hash 'contentFormat '("plaintext" "markdown"))
                                                 'publishDiagnostics (hash 'relatedInformation #t))
                                  'workspace (hash 'workspaceFolders #t)))
             #:id init-id)
  
  ;; Wait for initialize response
  (define resp (lsp-receive! lang #:timeout 10))
  (when resp
    (log-debug 1 'lsp "LSP initialized: ~a" (hash-ref resp 'result #f))
    ;; Send initialized notification
    (lsp-send! lang "initialized" (hash)))
  
  (format "Started LSP server for ~a" lang))

(define (lsp-stop! lang)
  (define server (hash-ref lsp-servers lang #f))
  (when server
    (with-handlers ([exn:fail? void])
      ;; Send shutdown
      (lsp-send! lang "shutdown" (hash) #:id (next-request-id! lang))
      (lsp-receive! lang #:timeout 2)
      ;; Send exit
      (lsp-send! lang "exit" (hash))
      ;; Kill process
      (subprocess-kill (hash-ref server 'process) #t))
    (hash-remove! lsp-servers lang))
  (format "Stopped LSP server for ~a" lang))

(define (lsp-list-servers)
  (for/list ([lang (in-hash-keys lsp-servers)])
    (hash 'language lang 'running #t)))

(define (lsp-status)
  (for/hash ([lang (in-hash-keys lsp-servers)])
    (values lang (subprocess-status (hash-ref (hash-ref lsp-servers lang) 'process)))))

;; ============================================================================
;; LSP FEATURES
;; ============================================================================

(define (file->uri path)
  (format "file://~a" (if (path? path) (path->string path) path)))

(define (lsp-open-file! lang path)
  (define content (file->string path))
  (lsp-send! lang "textDocument/didOpen"
             (hash 'textDocument
                   (hash 'uri (file->uri path)
                         'languageId lang
                         'version 1
                         'text content))))

(define (lsp-get-diagnostics path)
  (define lang (path->language path))
  (unless lang
    (error 'lsp-get-diagnostics "Unknown file type: ~a" path))
  
  ;; Start server if needed
  (unless (hash-has-key? lsp-servers lang)
    (lsp-start! lang #:root-path (path-only (string->path path))))
  
  ;; Open file
  (lsp-open-file! lang path)
  
  ;; Diagnostics are pushed via notifications, so we need to wait and collect
  (define diagnostics '())
  (for ([_ (in-range 10)])  ;; Try reading up to 10 messages
    (define msg (lsp-receive! lang #:timeout 1))
    (when (and msg (equal? (hash-ref msg 'method #f) "textDocument/publishDiagnostics"))
      (define params (hash-ref msg 'params (hash)))
      (when (equal? (hash-ref params 'uri #f) (file->uri path))
        (set! diagnostics (hash-ref params 'diagnostics '())))))
  
  diagnostics)

(define (lsp-hover path line column)
  (define lang (path->language path))
  (unless lang
    (error 'lsp-hover "Unknown file type: ~a" path))
  
  (unless (hash-has-key? lsp-servers lang)
    (lsp-start! lang #:root-path (path-only (string->path path))))
  
  (lsp-open-file! lang path)
  
  (define id (next-request-id! lang))
  (lsp-send! lang "textDocument/hover"
             (hash 'textDocument (hash 'uri (file->uri path))
                   'position (hash 'line (sub1 line) 'character (sub1 column)))
             #:id id)
  
  (define resp (lsp-receive! lang #:timeout 5))
  (and resp (hash-ref resp 'result #f)))

(define (lsp-definition path line column)
  (define lang (path->language path))
  (unless lang
    (error 'lsp-definition "Unknown file type: ~a" path))
  
  (unless (hash-has-key? lsp-servers lang)
    (lsp-start! lang #:root-path (path-only (string->path path))))
  
  (lsp-open-file! lang path)
  
  (define id (next-request-id! lang))
  (lsp-send! lang "textDocument/definition"
             (hash 'textDocument (hash 'uri (file->uri path))
                   'position (hash 'line (sub1 line) 'character (sub1 column)))
             #:id id)
  
  (define resp (lsp-receive! lang #:timeout 5))
  (and resp (hash-ref resp 'result #f)))

;; ============================================================================
;; TOOL INTERFACE
;; ============================================================================

(define (make-lsp-tools)
  (list
   (hash 'type "function"
         'function (hash 'name "lsp_diagnostics"
                         'description "Get compiler/linter diagnostics for a file using LSP. Returns errors, warnings, and hints."
                         'parameters (hash 'type "object"
                                           'properties (hash 'path (hash 'type "string" 'description "Absolute path to file"))
                                           'required '("path"))))
   (hash 'type "function"
         'function (hash 'name "lsp_hover"
                         'description "Get type information and documentation for a symbol at a position."
                         'parameters (hash 'type "object"
                                           'properties (hash 'path (hash 'type "string" 'description "Absolute path to file")
                                                             'line (hash 'type "integer" 'description "1-indexed line number")
                                                             'column (hash 'type "integer" 'description "1-indexed column number"))
                                           'required '("path" "line" "column"))))
   (hash 'type "function"
         'function (hash 'name "lsp_definition"
                         'description "Go to definition of a symbol at a position."
                         'parameters (hash 'type "object"
                                           'properties (hash 'path (hash 'type "string" 'description "Absolute path to file")
                                                             'line (hash 'type "integer" 'description "1-indexed line number")
                                                             'column (hash 'type "integer" 'description "1-indexed column number"))
                                           'required '("path" "line" "column"))))))

(define (execute-lsp-tool name args)
  (with-handlers ([exn:fail? (λ (e) (format "LSP Error: ~a" (exn-message e)))])
    (match name
      ["lsp_diagnostics"
       (define diags (lsp-get-diagnostics (hash-ref args 'path)))
       (if (null? diags)
           "No diagnostics"
           (string-join
            (for/list ([d (in-list diags)])
              (define range (hash-ref d 'range (hash)))
              (define start (hash-ref range 'start (hash)))
              (define sev (match (hash-ref d 'severity 1)
                           [1 "ERROR"] [2 "WARNING"] [3 "INFO"] [4 "HINT"] [_ "?"]))
              (format "~a:~a: [~a] ~a"
                      (add1 (hash-ref start 'line 0))
                      (add1 (hash-ref start 'character 0))
                      sev
                      (hash-ref d 'message "")))
            "\n"))]
      
      ["lsp_hover"
       (define result (lsp-hover (hash-ref args 'path)
                                 (hash-ref args 'line)
                                 (hash-ref args 'column)))
       (if result
           (let ([contents (hash-ref result 'contents #f)])
             (cond
               [(string? contents) contents]
               [(hash? contents) (hash-ref contents 'value "")]
               [(list? contents) (string-join (map (λ (c) (if (hash? c) (hash-ref c 'value "") c)) contents) "\n")]
               [else "No hover info"]))
           "No hover info")]
      
      ["lsp_definition"
       (define result (lsp-definition (hash-ref args 'path)
                                      (hash-ref args 'line)
                                      (hash-ref args 'column)))
       (cond
         [(not result) "Definition not found"]
         [(hash? result)
          (format "~a:~a:~a"
                  (hash-ref result 'uri "")
                  (add1 (hash-ref (hash-ref (hash-ref result 'range (hash)) 'start (hash)) 'line 0))
                  (add1 (hash-ref (hash-ref (hash-ref result 'range (hash)) 'start (hash)) 'character 0)))]
         [(list? result)
          (string-join
           (for/list ([r (in-list result)])
             (format "~a:~a"
                     (hash-ref r 'uri "")
                     (add1 (hash-ref (hash-ref (hash-ref r 'range (hash)) 'start (hash)) 'line 0))))
           "\n")]
         [else "Definition not found"])]
      
      [_ (format "Unknown LSP tool: ~a" name)])))

;; Helper: Get process ID
(define (getpid)
  (let ([s (with-output-to-string (λ () (system "echo $$")))])
    (string->number (string-trim s))))
