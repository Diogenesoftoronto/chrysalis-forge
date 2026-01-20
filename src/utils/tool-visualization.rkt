#lang racket/base
(provide tool-start!
         tool-complete!
         tool-error!
         tool-preview
         with-tool-viz
         show-tool-status)

(require racket/format
         racket/string
         racket/list
         racket/match
         (for-syntax racket/base)
         "utils-spinner.rkt")

;; ANSI color codes
(define RESET "\033[0m")
(define BOLD "\033[1m")
(define DIM "\033[2m")
(define CYAN "\033[36m")
(define GREEN "\033[32m")
(define RED "\033[31m")
(define YELLOW "\033[33m")
(define MAGENTA "\033[35m")

;; Tool icons by category
(define (tool-icon tool-name)
  (define name (if (symbol? tool-name) (symbol->string tool-name) tool-name))
  (cond
    [(or (string-contains? name "read_file")
         (string-contains? name "write_file")
         (string-contains? name "patch_file")
         (string-contains? name "list_dir")
         (string-contains? name "file")) "📄"]
    [(or (string-contains? name "git_")
         (string-contains? name "jj_")) "🔀"]
    [(or (string-contains? name "grep")
         (string-contains? name "search")) "🔍"]
    [(or (string-contains? name "http")
         (string-contains? name "fetch")
         (string-contains? name "mcp")) "🌐"]
    [else "⚙"]))

;; Format parameters for display
(define (format-params params)
  (if (or (not params) (hash-empty? params))
      ""
      (let ([pairs (for/list ([(k v) (in-hash params)])
                     (format "~a: ~a" k (truncate-value v 30)))])
        (format "(~a)" (string-join pairs ", ")))))

(define (truncate-value v max-len)
  (define s (format "~a" v))
  (if (> (string-length s) max-len)
      (string-append (substring s 0 (- max-len 3)) "...")
      s))

;; Format duration for display
(define (format-duration ms)
  (cond
    [(< ms 1000) (format "~ams" (inexact->exact (round ms)))]
    [(< ms 60000) (format "~as" (real->decimal-string (/ ms 1000.0) 1))]
    [else (format "~am" (real->decimal-string (/ ms 60000.0) 1))]))

;; Active spinners tracking
(define active-spinners (make-hash))

;; Show tool starting
(define (tool-start! tool-name #:params [params (hash)])
  (define out (current-error-port))
  (define name-str (if (symbol? tool-name) (symbol->string tool-name) tool-name))
  (define icon (tool-icon name-str))
  (define param-str (format-params params))
  
  ;; Start spinner for this tool
  (define spinner-thread
    (thread
     (λ ()
       (let loop ([frames '("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")])
         (define frame (first frames))
         (define next (if (null? (rest frames)) '("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏") (rest frames)))
         (fprintf out "\r\033[K~a ~a~a~a~a ~a~a~a"
                  frame icon CYAN BOLD name-str RESET DIM param-str)
         (flush-output out)
         (sleep 0.08)
         (loop next)))))
  
  (hash-set! active-spinners name-str spinner-thread)
  name-str)

;; Stop spinner for a tool
(define (stop-tool-spinner! name-str)
  (define t (hash-ref active-spinners name-str #f))
  (when (and t (thread? t))
    (kill-thread t)
    (hash-remove! active-spinners name-str)))

;; Show tool success
(define (tool-complete! tool-name result #:duration-ms [ms 0])
  (define out (current-error-port))
  (define name-str (if (symbol? tool-name) (symbol->string tool-name) tool-name))
  (define icon (tool-icon name-str))
  
  (stop-tool-spinner! name-str)
  
  (fprintf out "\r\033[K~a~a✓~a ~a ~a~a~a ~a[~a]~a\n"
           BOLD GREEN RESET icon name-str
           DIM (format-duration ms) RESET
           DIM RESET)
  (flush-output out))

;; Show tool error
(define (tool-error! tool-name error-message)
  (define out (current-error-port))
  (define name-str (if (symbol? tool-name) (symbol->string tool-name) tool-name))
  (define icon (tool-icon name-str))
  (define err-snippet (truncate-value error-message 60))
  
  (stop-tool-spinner! name-str)
  
  (fprintf out "\r\033[K~a~a✗~a ~a ~a ~a~a~a\n"
           BOLD RED RESET icon name-str
           RED err-snippet RESET)
  (flush-output out))

;; Preview result with truncation
(define (tool-preview result #:max-lines [max-lines 5] #:max-width [max-width 80])
  (define out (current-error-port))
  (define result-str (format "~a" result))
  (define lines (string-split result-str "\n"))
  (define truncated-lines
    (for/list ([line (take lines (min max-lines (length lines)))]
               [i (in-naturals)])
      (if (> (string-length line) max-width)
          (string-append (substring line 0 (- max-width 3)) "...")
          line)))
  
  (define more-lines (- (length lines) max-lines))
  
  (fprintf out "~a│~a " DIM RESET)
  (fprintf out "~a\n" (string-join truncated-lines (format "\n~a│~a " DIM RESET)))
  
  (when (> more-lines 0)
    (fprintf out "~a│ ... ~a more lines~a\n" DIM more-lines RESET))
  
  (flush-output out))

;; Show tool status indicator
(define (show-tool-status tool-name status)
  (define out (current-error-port))
  (define name-str (if (symbol? tool-name) (symbol->string tool-name) tool-name))
  (define icon (tool-icon name-str))
  
  (match status
    ['running
     (fprintf out "~a⟳~a ~a ~a~a~a\n" CYAN RESET icon CYAN name-str RESET)]
    ['success
     (fprintf out "~a✓~a ~a ~a~a~a\n" GREEN RESET icon GREEN name-str RESET)]
    ['error
     (fprintf out "~a✗~a ~a ~a~a~a\n" RED RESET icon RED name-str RESET)]
    ['skipped
     (fprintf out "~a⊘~a ~a ~a~a~a\n" YELLOW RESET icon DIM name-str RESET)]
    [_
     (fprintf out "~a?~a ~a ~a\n" DIM RESET icon name-str)])
  
  (flush-output out))

;; Macro wrapper for automatic visualization
(define-syntax with-tool-viz
  (syntax-rules ()
    [(_ tool-name params body ...)
     (let ([name tool-name]
           [start-time (current-inexact-milliseconds)])
       (tool-start! name #:params params)
       (with-handlers
         ([exn:fail?
           (λ (e)
             (tool-error! name (exn-message e))
             (raise e))])
         (let ([result (begin body ...)])
           (tool-complete! name result
                           #:duration-ms (- (current-inexact-milliseconds) start-time))
           result)))]))
