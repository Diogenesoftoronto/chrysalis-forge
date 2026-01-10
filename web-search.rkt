#lang racket/base
(provide make-web-search-tools execute-web-search)
(require json racket/file racket/string racket/system racket/port racket/format "debug.rkt")

;; ============================================================================
;; WEB SEARCH - Exa API with curl fallback
;; ============================================================================

(define EXA-API-URL "https://api.exa.ai/search")
(define EXA-CONTENTS-URL "https://api.exa.ai/contents")

;; Get Exa API key from environment
(define (get-exa-key)
  (getenv "EXA_API_KEY"))

;; Tool definitions for web search
(define (make-web-search-tools)
  (list
   (hash 'type "function"
         'function (hash 'name "web_search"
                         'description "Search the web using Exa AI. Falls back to curl if no API key."
                         'parameters (hash 'type "object"
                                           'properties (hash 'query (hash 'type "string" 'description "Search query")
                                                             'num_results (hash 'type "integer" 'description "Number of results (default 5)")
                                                             'type (hash 'type "string" 'description "Search type: 'auto' (default), 'neural', 'keyword', 'fast', 'deep'")
                                                             'include_text (hash 'type "boolean" 'description "Include page text in results"))
                                           'required '("query"))))
   (hash 'type "function"
         'function (hash 'name "web_fetch"
                         'description "Fetch content from a URL using curl. Returns the page content."
                         'parameters (hash 'type "object"
                                           'properties (hash 'url (hash 'type "string" 'description "URL to fetch"))
                                           'required '("url"))))
   (hash 'type "function"
         'function (hash 'name "web_search_news"
                         'description "Search recent news articles using Exa's neural search with date filtering."
                         'parameters (hash 'type "object"
                                           'properties (hash 'query (hash 'type "string" 'description "News search query")
                                                             'days_back (hash 'type "integer" 'description "How many days back to search (default 7)"))
                                           'required '("query"))))))

;; Execute web search tools
(define (execute-web-search name args)
  (match name
    ["web_search" (exa-search args)]
    ["web_fetch" (curl-fetch (hash-ref args 'url))]
    ["web_search_news" (exa-news-search args)]
    [_ (format "Unknown web tool: ~a" name)]))

;; Exa search implementation
(define (exa-search args)
  (define api-key (get-exa-key))
  (define query (hash-ref args 'query))
  (define num-results (hash-ref args 'num_results 5))
  (define search-type (hash-ref args 'type "auto"))
  (define include-text? (hash-ref args 'include_text #f))
  
  (if api-key
      (begin
        (log-debug 1 'web "Using Exa API for query: ~a" query)
        (exa-api-search query num-results search-type include-text? api-key))
      (begin
        (log-debug 1 'web "No EXA_API_KEY found. Using fallback search for query: ~a" query)
        (curl-search-fallback query num-results))))

;; Exa API call
(define (exa-api-search query num-results search-type include-text? api-key)
  (define body (jsexpr->string
                (hash 'query query
                      'numResults num-results
                      'type search-type
                      'contents (if include-text? 
                                    (hash 'text (hash 'maxCharacters 2000))
                                    (hash)))))
  
  (define url (if include-text? EXA-CONTENTS-URL EXA-API-URL))
  
  (define-values (sp stdout stdin stderr)
    (subprocess #f #f #f (find-executable-path "curl")
                "-s" "-X" "POST" url
                "-H" "Content-Type: application/json"
                "-H" (format "x-api-key: ~a" api-key)
                "-d" body))
  (close-output-port stdin)
  (define output (port->string stdout))
  (define errors (port->string stderr))
  (subprocess-wait sp)
  (close-input-port stdout)
  (close-input-port stderr)
  
  (if (string=? output "")
      (format "Search failed: ~a" errors)
      (format-exa-results output)))

;; Format Exa results
(define (format-exa-results json-str)
  (with-handlers ([exn:fail? (λ (e) (format "Parse error: ~a\nRaw: ~a" (exn-message e) json-str))])
    (define data (string->jsexpr json-str))
    
    (cond
      [(hash-has-key? data 'error) 
       (format "Exa API Error: ~a" (hash-ref data 'error))]
      [(hash-has-key? data 'message) 
       (format "Exa API Message: ~a" (hash-ref data 'message))]
      [else
       (define results (hash-ref data 'results '()))
       (if (null? results)
           "No results found."
           (string-join
            (for/list ([r results] [i (in-naturals 1)])
              (format "~a. ~a\n   ~a\n   ~a"
                      i
                      (hash-ref r 'title "Untitled")
                      (hash-ref r 'url "")
                      (let ([text (hash-ref r 'text #f)])
                        (if text (string-truncate text 200) ""))))
            "\n\n"))])))

;; String truncate helper
(define (string-truncate s max-len)
  (if (<= (string-length s) max-len)
      s
      (string-append (substring s 0 max-len) "...")))

;; Curl fallback using DuckDuckGo HTML API
(define (curl-search-fallback query num-results)
  (define url (format "https://html.duckduckgo.com/html/?q=~a" (url-encode query)))
  (define-values (sp stdout stdin stderr)
    (subprocess #f #f #f (find-executable-path "curl")
                "-s" "-A" "Mozilla/5.0" url))
  (close-output-port stdin)
  (define output (port->string stdout))
  (subprocess-wait sp)
  (close-input-port stdout)
  (close-input-port stderr)
  
  ;; Simple extraction of result snippets
  (extract-ddg-results output num-results))

;; Extract DuckDuckGo results from HTML
(define (extract-ddg-results html num)
  (define results '())
  (define lines (string-split html "\n"))
  (for ([line lines])
    (when (and (< (length results) num)
               (string-contains? line "result__a"))
      ;; Very basic extraction - in practice would need proper HTML parsing
      (set! results (cons line results))))
  (if (null? results)
      (format "Fallback search returned no results. Raw length: ~a chars" (string-length html))
      (format "Found ~a results (fallback mode - no EXA_API_KEY set)" (length results))))

;; URL encode helper
(define (url-encode s)
  (string-join
   (for/list ([c (string->list s)])
     (cond
       [(char-alphabetic? c) (string c)]
       [(char-numeric? c) (string c)]
       [(member c '(#\- #\_ #\. #\~)) (string c)]
       [else (format "%~a" (number->string (char->integer c) 16))]))
   ""))

;; Simple curl fetch
(define (curl-fetch url)
  (log-debug 1 'web "Fetching URL: ~a" url)
  (define-values (sp stdout stdin stderr)
    (subprocess #f #f #f (find-executable-path "curl")
                "-s" "-L" "-A" "Mozilla/5.0" url))
  (close-output-port stdin)
  (define output (port->string stdout))
  (subprocess-wait sp)
  (close-input-port stdout)
  (close-input-port stderr)
  
  (if (> (string-length output) 10000)
      (string-append (substring output 0 10000) "\n...[truncated]")
      output))

;; Exa news search (with date filtering)
(define (exa-news-search args)
  (log-debug 1 'web "Searching news: ~a" (hash-ref args 'query))
  (define api-key (get-exa-key))
  (define query (hash-ref args 'query))
  (define days-back (hash-ref args 'days_back 7))
  
  (if api-key
      (let* ([now (current-seconds)]
             [past (- now (* days-back 86400))]
             [body (jsexpr->string
                    (hash 'query query
                          'numResults 10
                          'type "neural"
                          'category "news"
                          'startPublishedDate (seconds->iso8601 past)))])
        (define-values (sp stdout stdin stderr)
          (subprocess #f #f #f (find-executable-path "curl")
                      "-s" "-X" "POST" EXA-API-URL
                      "-H" "Content-Type: application/json"
                      "-H" (format "x-api-key: ~a" api-key)
                      "-d" body))
        (close-output-port stdin)
        (define output (port->string stdout))
        (subprocess-wait sp)
        (close-input-port stdout)
        (close-input-port stderr)
        (format-exa-results output))
      "News search requires EXA_API_KEY"))

;; Convert seconds to ISO 8601 date
(define (seconds->iso8601 secs)
  (define d (seconds->date secs))
  (format "~a-~a-~aT00:00:00Z"
          (date-year d)
          (~r (date-month d) #:min-width 2 #:pad-string "0")
          (~r (date-day d) #:min-width 2 #:pad-string "0")))

(require racket/match)
