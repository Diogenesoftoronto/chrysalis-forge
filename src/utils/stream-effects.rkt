#lang racket/base
;; Streaming Output Effects for CLI
;; Provides typewriter, word-by-word, and line-by-line streaming with markdown formatting.

(provide
 ;; Streaming functions
 stream-typewriter
 stream-word-by-word
 stream-line-by-line
 stream-with-formatting
 
 ;; Markdown detection
 detect-code-blocks
 
 ;; Streamer object
 make-streamer
 streamer-write!
 streamer-flush!
 streamer-finish!)

(require racket/string
         racket/match
         "terminal-style.rkt")

;; ---------------------------------------------------------------------------
;; Streaming Primitives
;; ---------------------------------------------------------------------------

(define (stream-typewriter text
                           #:delay [delay 0.03]
                           #:out [out (current-output-port)])
  (for ([c (in-string text)])
    (display c out)
    (flush-output out)
    (sleep delay)))

(define (stream-word-by-word text
                             #:delay [delay 0.1]
                             #:out [out (current-output-port)])
  (define words (string-split text))
  (for ([word (in-list words)]
        [i (in-naturals)])
    (when (> i 0)
      (display " " out))
    (display word out)
    (flush-output out)
    (sleep delay)))

(define (stream-line-by-line text
                             #:delay [delay 0.2]
                             #:out [out (current-output-port)])
  (define lines (string-split text "\n"))
  (for ([line (in-list lines)]
        [i (in-naturals)])
    (when (> i 0)
      (newline out))
    (display line out)
    (flush-output out)
    (sleep delay)))

;; ---------------------------------------------------------------------------
;; Markdown Detection
;; ---------------------------------------------------------------------------

(struct code-block (lang start-pos end-pos content) #:transparent)

(define (detect-code-blocks text)
  (define pattern #px"```([a-zA-Z0-9]*)\n((?:.|[\n])*?)```")
  (define matches (regexp-match-positions* pattern text))
  (for/list ([m (in-list matches)])
    (define full-match (substring text (car m) (cdr m)))
    (define inner (regexp-match #px"```([a-zA-Z0-9]*)\n((?:.|[\n])*?)```" full-match))
    (if inner
        (code-block (cadr inner)
                    (car m)
                    (cdr m)
                    (caddr inner))
        (code-block "" (car m) (cdr m) ""))))

(define (apply-inline-formatting line)
  (define result line)
  (set! result (regexp-replace* #px"\\*\\*([^*]+)\\*\\*" result
                                (λ (all content) (bold content))))
  (set! result (regexp-replace* #px"(?<!\\*)\\*([^*]+)\\*(?!\\*)" result
                                (λ (all content) (italic content))))
  (set! result (regexp-replace* #px"`([^`]+)`" result
                                (λ (all content) (dim content))))
  result)

(define (format-markdown-line line)
  (cond
    [(regexp-match #px"^(#{1,6})\\s+(.+)$" line)
     => (λ (m) (bold (caddr m)))]
    [else
     (apply-inline-formatting line)]))

;; ---------------------------------------------------------------------------
;; Streaming with Formatting
;; ---------------------------------------------------------------------------

(define (stream-with-formatting text
                                #:delay [delay 0.05]
                                #:out [out (current-output-port)])
  (define blocks (detect-code-blocks text))
  (define block-positions
    (for/fold ([positions (hasheq)])
              ([b (in-list blocks)])
      (hash-set positions (code-block-start-pos b) b)))
  
  (define lines (string-split text "\n"))
  (define current-pos 0)
  (define in-code-block? #f)
  (define code-block-lang "")
  
  (for ([line (in-list lines)]
        [i (in-naturals)])
    (when (> i 0)
      (newline out))
    
    (cond
      [(regexp-match #px"^```(\\w*)$" line)
       => (λ (m)
            (if in-code-block?
                (begin
                  (set! in-code-block? #f)
                  (display (dim "───") out))
                (begin
                  (set! in-code-block? #t)
                  (set! code-block-lang (or (cadr m) ""))
                  (display (dim (format "─── ~a ───" 
                                        (if (string=? code-block-lang "")
                                            "code"
                                            code-block-lang))) out))))]
      [in-code-block?
       (display (dim line) out)]
      [else
       (define formatted (format-markdown-line line))
       (for ([c (in-string formatted)])
         (display c out)
         (flush-output out)
         (sleep delay))])
    
    (flush-output out)
    (set! current-pos (+ current-pos (string-length line) 1))))

;; ---------------------------------------------------------------------------
;; Streamer Object
;; ---------------------------------------------------------------------------

(struct streamer (buffer out delay mode) #:mutable #:transparent)

(define (make-streamer #:out [out (current-output-port)]
                       #:delay [delay 0.03]
                       #:mode [mode 'typewriter])
  (streamer (make-string 0) out delay mode))

(define (streamer-write! s text)
  (define out (streamer-out s))
  (define delay (streamer-delay s))
  
  (case (streamer-mode s)
    [(typewriter)
     (for ([c (in-string text)])
       (display c out)
       (flush-output out)
       (sleep delay))]
    [(word)
     (define words (string-split text))
     (for ([word (in-list words)]
           [i (in-naturals)])
       (when (> i 0)
         (display " " out))
       (display word out)
       (flush-output out)
       (sleep delay))]
    [(line)
     (define lines (string-split text "\n"))
     (for ([line (in-list lines)]
           [i (in-naturals)])
       (when (> i 0)
         (newline out))
       (display line out)
       (flush-output out)
       (sleep delay))]
    [(formatted)
     (stream-with-formatting text #:delay delay #:out out)]
    [else
     (display text out)
     (flush-output out)]))

(define (streamer-flush! s)
  (flush-output (streamer-out s)))

(define (streamer-finish! s)
  (flush-output (streamer-out s))
  (newline (streamer-out s)))

;; ---------------------------------------------------------------------------
;; Tests
;; ---------------------------------------------------------------------------

(module+ test
  (require rackunit)
  
  (test-case "detect-code-blocks finds fenced blocks"
    (define text "Hello\n```python\nprint('hi')\n```\nWorld")
    (define blocks (detect-code-blocks text))
    (check-equal? (length blocks) 1)
    (check-equal? (code-block-lang (car blocks)) "python"))
  
  (test-case "detect-code-blocks handles empty lang"
    (define text "```\ncode\n```")
    (define blocks (detect-code-blocks text))
    (check-equal? (length blocks) 1)
    (check-equal? (code-block-lang (car blocks)) ""))
  
  (test-case "format-markdown-line handles headers"
    (parameterize ([color-enabled-param #t])
      (define result (format-markdown-line "# Header"))
      (check-true (string-contains? result "Header"))))
  
  (test-case "streamer creation"
    (define s (make-streamer #:delay 0.01 #:mode 'typewriter))
    (check-equal? (streamer-delay s) 0.01)
    (check-equal? (streamer-mode s) 'typewriter)))
