#lang racket/base

(require racket/string
         racket/list
         racket/match)

(provide (struct-out text-buffer)
         make-buffer
         buffer-empty
         
         ;; Cursor operations
         buffer-move-left
         buffer-move-right
         buffer-move-word-left
         buffer-move-word-right
         buffer-move-home
         buffer-move-end
         buffer-move-up
         buffer-move-down
         buffer-move-to
         
         ;; Editing operations
         buffer-insert
         buffer-delete-char
         buffer-delete-forward
         buffer-delete-word
         buffer-delete-to-end
         buffer-delete-to-start
         buffer-delete-selection
         buffer-replace-selection
         
         ;; Selection
         buffer-select-all
         buffer-select-word
         buffer-select-to
         buffer-clear-selection
         buffer-has-selection?
         buffer-get-selection
         buffer-selection-range
         
         ;; Queries
         buffer-text
         buffer-cursor
         buffer-length
         buffer-line-count
         buffer-current-line
         buffer-current-column
         buffer-line-start
         buffer-line-end)

;; ============================================================================
;; Text Buffer Struct
;; ============================================================================

(struct text-buffer (text cursor selection)
  #:transparent
  #:guard (λ (text cursor selection name)
            (define len (string-length text))
            (define clamped-cursor (max 0 (min cursor len)))
            (define normalized-selection
              (match selection
                [(cons start end)
                 (define s (max 0 (min start len)))
                 (define e (max 0 (min end len)))
                 (if (= s e) #f (cons (min s e) (max s e)))]
                [_ #f]))
            (values text clamped-cursor normalized-selection)))

(define buffer-empty (text-buffer "" 0 #f))

(define (make-buffer [text ""] #:cursor [cursor #f])
  (text-buffer text (or cursor (string-length text)) #f))

;; ============================================================================
;; Helper Functions
;; ============================================================================

(define (word-boundary? c)
  (or (char-whitespace? c)
      (memq c '(#\( #\) #\[ #\] #\{ #\} #\< #\> #\, #\. #\; #\: #\' #\" #\` #\- #\_ #\/ #\\))))

(define (find-word-start text pos)
  (if (<= pos 0)
      0
      (let loop ([i (sub1 pos)])
        (cond
          [(< i 0) 0]
          [(and (word-boundary? (string-ref text i))
                (or (= i (sub1 pos))
                    (not (word-boundary? (string-ref text (add1 i))))))
           (add1 i)]
          [(word-boundary? (string-ref text i))
           (loop (sub1 i))]
          [(= i 0) 0]
          [else (loop (sub1 i))]))))

(define (find-word-end text pos)
  (define len (string-length text))
  (if (>= pos len)
      len
      (let loop ([i pos])
        (cond
          [(>= i len) len]
          [(word-boundary? (string-ref text i))
           (let inner ([j (add1 i)])
             (cond
               [(>= j len) len]
               [(word-boundary? (string-ref text j)) (inner (add1 j))]
               [else j]))]
          [else (loop (add1 i))]))))

(define (line-positions text)
  (define len (string-length text))
  (let loop ([i 0] [line-starts '(0)])
    (if (>= i len)
        (reverse line-starts)
        (if (char=? (string-ref text i) #\newline)
            (loop (add1 i) (cons (add1 i) line-starts))
            (loop (add1 i) line-starts)))))

(define (pos->line+col text pos)
  (define starts (line-positions text))
  (let loop ([starts starts] [line 0])
    (match starts
      [(list start) (values line (- pos start))]
      [(cons start (cons next rest))
       (if (< pos next)
           (values line (- pos start))
           (loop (cons next rest) (add1 line)))]
      [_ (values 0 pos)])))

(define (line+col->pos text line col)
  (define starts (line-positions text))
  (define line-start (if (< line (length starts))
                         (list-ref starts line)
                         (last starts)))
  (define line-end (buffer-line-end-pos text line-start))
  (min (+ line-start col) line-end))

(define (buffer-line-end-pos text pos)
  (define len (string-length text))
  (let loop ([i pos])
    (cond
      [(>= i len) len]
      [(char=? (string-ref text i) #\newline) i]
      [else (loop (add1 i))])))

(define (buffer-line-start-pos text pos)
  (if (<= pos 0)
      0
      (let loop ([i (sub1 pos)])
        (cond
          [(< i 0) 0]
          [(char=? (string-ref text i) #\newline) (add1 i)]
          [else (loop (sub1 i))]))))

;; ============================================================================
;; Cursor Operations
;; ============================================================================

(define (buffer-move-left buf)
  (match-define (text-buffer text cursor _) buf)
  (text-buffer text (max 0 (sub1 cursor)) #f))

(define (buffer-move-right buf)
  (match-define (text-buffer text cursor _) buf)
  (text-buffer text (min (string-length text) (add1 cursor)) #f))

(define (buffer-move-word-left buf)
  (match-define (text-buffer text cursor _) buf)
  (if (<= cursor 0)
      buf
      (let* ([i (sub1 cursor)]
             [i (let skip-space ([j i])
                  (if (and (>= j 0) (char-whitespace? (string-ref text j)))
                      (skip-space (sub1 j))
                      j))]
             [new-pos (if (< i 0)
                          0
                          (let find-word ([j i])
                            (cond
                              [(< j 0) 0]
                              [(word-boundary? (string-ref text j)) (add1 j)]
                              [else (find-word (sub1 j))])))])
        (text-buffer text new-pos #f))))

(define (buffer-move-word-right buf)
  (match-define (text-buffer text cursor _) buf)
  (define len (string-length text))
  (if (>= cursor len)
      buf
      (let* ([i cursor]
             [i (let skip-word ([j i])
                  (if (and (< j len) (not (word-boundary? (string-ref text j))))
                      (skip-word (add1 j))
                      j))]
             [new-pos (let skip-space ([j i])
                        (if (and (< j len) (char-whitespace? (string-ref text j)))
                            (skip-space (add1 j))
                            j))])
        (text-buffer text new-pos #f))))

(define (buffer-move-home buf)
  (match-define (text-buffer text cursor _) buf)
  (text-buffer text (buffer-line-start-pos text cursor) #f))

(define (buffer-move-end buf)
  (match-define (text-buffer text cursor _) buf)
  (text-buffer text (buffer-line-end-pos text cursor) #f))

(define (buffer-move-up buf)
  (match-define (text-buffer text cursor _) buf)
  (define-values (line col) (pos->line+col text cursor))
  (if (= line 0)
      buf
      (text-buffer text (line+col->pos text (sub1 line) col) #f)))

(define (buffer-move-down buf)
  (match-define (text-buffer text cursor _) buf)
  (define-values (line col) (pos->line+col text cursor))
  (define num-lines (buffer-line-count buf))
  (if (>= line (sub1 num-lines))
      buf
      (text-buffer text (line+col->pos text (add1 line) col) #f)))

(define (buffer-move-to buf pos)
  (match-define (text-buffer text _ selection) buf)
  (text-buffer text pos selection))

;; ============================================================================
;; Editing Operations
;; ============================================================================

(define (buffer-insert buf str)
  (match-define (text-buffer text cursor selection) buf)
  (cond
    [selection
     (buffer-insert (buffer-delete-selection buf) str)]
    [else
     (define before (substring text 0 cursor))
     (define after (substring text cursor))
     (text-buffer (string-append before str after)
                  (+ cursor (string-length str))
                  #f)]))

(define (buffer-delete-char buf)
  (match-define (text-buffer text cursor selection) buf)
  (cond
    [selection (buffer-delete-selection buf)]
    [(<= cursor 0) buf]
    [else
     (define before (substring text 0 (sub1 cursor)))
     (define after (substring text cursor))
     (text-buffer (string-append before after) (sub1 cursor) #f)]))

(define (buffer-delete-forward buf)
  (match-define (text-buffer text cursor selection) buf)
  (cond
    [selection (buffer-delete-selection buf)]
    [(>= cursor (string-length text)) buf]
    [else
     (define before (substring text 0 cursor))
     (define after (substring text (add1 cursor)))
     (text-buffer (string-append before after) cursor #f)]))

(define (buffer-delete-word buf)
  (match-define (text-buffer text cursor _) buf)
  (if (<= cursor 0)
      buf
      (let* ([word-start (let skip-space ([j (sub1 cursor)])
                           (if (and (>= j 0) (char-whitespace? (string-ref text j)))
                               (skip-space (sub1 j))
                               j))]
             [word-start (if (< word-start 0)
                             0
                             (let find-word ([j word-start])
                               (cond
                                 [(< j 0) 0]
                                 [(word-boundary? (string-ref text j)) (add1 j)]
                                 [else (find-word (sub1 j))])))]
             [before (substring text 0 word-start)]
             [after (substring text cursor)])
        (text-buffer (string-append before after) word-start #f))))

(define (buffer-delete-to-end buf)
  (match-define (text-buffer text cursor _) buf)
  (define line-end (buffer-line-end-pos text cursor))
  (if (= cursor line-end)
      buf
      (let ([before (substring text 0 cursor)]
            [after (substring text line-end)])
        (text-buffer (string-append before after) cursor #f))))

(define (buffer-delete-to-start buf)
  (match-define (text-buffer text cursor _) buf)
  (define line-start (buffer-line-start-pos text cursor))
  (if (= cursor line-start)
      buf
      (let ([before (substring text 0 line-start)]
            [after (substring text cursor)])
        (text-buffer (string-append before after) line-start #f))))

(define (buffer-delete-selection buf)
  (match-define (text-buffer text cursor selection) buf)
  (if (not selection)
      buf
      (match-let ([(cons start end) selection])
        (define before (substring text 0 start))
        (define after (substring text end))
        (text-buffer (string-append before after) start #f))))

(define (buffer-replace-selection buf str)
  (if (buffer-has-selection? buf)
      (buffer-insert (buffer-delete-selection buf) str)
      (buffer-insert buf str)))

;; ============================================================================
;; Selection Operations
;; ============================================================================

(define (buffer-select-all buf)
  (match-define (text-buffer text cursor _) buf)
  (define len (string-length text))
  (if (= len 0)
      buf
      (text-buffer text len (cons 0 len))))

(define (buffer-select-word buf)
  (match-define (text-buffer text cursor _) buf)
  (define len (string-length text))
  (if (or (= len 0) (>= cursor len))
      buf
      (let* ([start (let loop ([i cursor])
                      (cond
                        [(< i 0) 0]
                        [(word-boundary? (string-ref text i)) (add1 i)]
                        [else (loop (sub1 i))]))]
             [end (let loop ([i cursor])
                    (cond
                      [(>= i len) len]
                      [(word-boundary? (string-ref text i)) i]
                      [else (loop (add1 i))]))])
        (if (= start end)
            buf
            (text-buffer text end (cons start end))))))

(define (buffer-select-to buf pos)
  (match-define (text-buffer text cursor selection) buf)
  (define anchor (if selection (car selection) cursor))
  (text-buffer text pos (cons anchor pos)))

(define (buffer-clear-selection buf)
  (match-define (text-buffer text cursor _) buf)
  (text-buffer text cursor #f))

(define (buffer-has-selection? buf)
  (and (text-buffer-selection buf) #t))

(define (buffer-get-selection buf)
  (match-define (text-buffer text _ selection) buf)
  (if selection
      (match-let ([(cons start end) selection])
        (substring text start end))
      ""))

(define (buffer-selection-range buf)
  (text-buffer-selection buf))

;; ============================================================================
;; Query Operations
;; ============================================================================

(define (buffer-text buf)
  (text-buffer-text buf))

(define (buffer-cursor buf)
  (text-buffer-cursor buf))

(define (buffer-length buf)
  (string-length (text-buffer-text buf)))

(define (buffer-line-count buf)
  (define text (text-buffer-text buf))
  (if (string=? text "")
      1
      (add1 (for/sum ([c (in-string text)])
              (if (char=? c #\newline) 1 0)))))

(define (buffer-current-line buf)
  (match-define (text-buffer text cursor _) buf)
  (define-values (line _col) (pos->line+col text cursor))
  line)

(define (buffer-current-column buf)
  (match-define (text-buffer text cursor _) buf)
  (define-values (_line col) (pos->line+col text cursor))
  col)

(define (buffer-line-start buf)
  (match-define (text-buffer text cursor _) buf)
  (buffer-line-start-pos text cursor))

(define (buffer-line-end buf)
  (match-define (text-buffer text cursor _) buf)
  (buffer-line-end-pos text cursor))

;; ============================================================================
;; Tests
;; ============================================================================

(module+ test
  (require rackunit)
  
  (test-case "make-buffer creates empty buffer"
    (define buf (make-buffer))
    (check-equal? (buffer-text buf) "")
    (check-equal? (buffer-cursor buf) 0))
  
  (test-case "make-buffer with text"
    (define buf (make-buffer "hello"))
    (check-equal? (buffer-text buf) "hello")
    (check-equal? (buffer-cursor buf) 5))
  
  (test-case "make-buffer with cursor position"
    (define buf (make-buffer "hello" #:cursor 2))
    (check-equal? (buffer-cursor buf) 2))
  
  (test-case "buffer-move-left"
    (define buf (make-buffer "hello" #:cursor 3))
    (check-equal? (buffer-cursor (buffer-move-left buf)) 2)
    (define at-start (make-buffer "hello" #:cursor 0))
    (check-equal? (buffer-cursor (buffer-move-left at-start)) 0))
  
  (test-case "buffer-move-right"
    (define buf (make-buffer "hello" #:cursor 2))
    (check-equal? (buffer-cursor (buffer-move-right buf)) 3)
    (define at-end (make-buffer "hello"))
    (check-equal? (buffer-cursor (buffer-move-right at-end)) 5))
  
  (test-case "buffer-move-word-left"
    (define buf (make-buffer "hello world" #:cursor 11))
    (define moved (buffer-move-word-left buf))
    (check-equal? (buffer-cursor moved) 6))
  
  (test-case "buffer-move-word-right"
    (define buf (make-buffer "hello world" #:cursor 0))
    (define moved (buffer-move-word-right buf))
    (check-equal? (buffer-cursor moved) 6))
  
  (test-case "buffer-move-home"
    (define buf (make-buffer "line1\nline2" #:cursor 8))
    (define moved (buffer-move-home buf))
    (check-equal? (buffer-cursor moved) 6))
  
  (test-case "buffer-move-end"
    (define buf (make-buffer "line1\nline2" #:cursor 7))
    (define moved (buffer-move-end buf))
    (check-equal? (buffer-cursor moved) 11))
  
  (test-case "buffer-move-up"
    (define buf (make-buffer "line1\nline2" #:cursor 8))
    (define moved (buffer-move-up buf))
    (check-equal? (buffer-cursor moved) 2))
  
  (test-case "buffer-move-down"
    (define buf (make-buffer "line1\nline2" #:cursor 2))
    (define moved (buffer-move-down buf))
    (check-equal? (buffer-cursor moved) 8))
  
  (test-case "buffer-insert at end"
    (define buf (make-buffer "hello"))
    (define inserted (buffer-insert buf " world"))
    (check-equal? (buffer-text inserted) "hello world")
    (check-equal? (buffer-cursor inserted) 11))
  
  (test-case "buffer-insert in middle"
    (define buf (make-buffer "helo" #:cursor 3))
    (define inserted (buffer-insert buf "l"))
    (check-equal? (buffer-text inserted) "hello")
    (check-equal? (buffer-cursor inserted) 4))
  
  (test-case "buffer-delete-char"
    (define buf (make-buffer "hello" #:cursor 5))
    (define deleted (buffer-delete-char buf))
    (check-equal? (buffer-text deleted) "hell")
    (check-equal? (buffer-cursor deleted) 4))
  
  (test-case "buffer-delete-char at start"
    (define buf (make-buffer "hello" #:cursor 0))
    (define deleted (buffer-delete-char buf))
    (check-equal? (buffer-text deleted) "hello"))
  
  (test-case "buffer-delete-forward"
    (define buf (make-buffer "hello" #:cursor 0))
    (define deleted (buffer-delete-forward buf))
    (check-equal? (buffer-text deleted) "ello")
    (check-equal? (buffer-cursor deleted) 0))
  
  (test-case "buffer-delete-word"
    (define buf (make-buffer "hello world" #:cursor 11))
    (define deleted (buffer-delete-word buf))
    (check-equal? (buffer-text deleted) "hello "))
  
  (test-case "buffer-delete-to-end"
    (define buf (make-buffer "hello world" #:cursor 5))
    (define deleted (buffer-delete-to-end buf))
    (check-equal? (buffer-text deleted) "hello"))
  
  (test-case "buffer-delete-to-start"
    (define buf (make-buffer "hello world" #:cursor 6))
    (define deleted (buffer-delete-to-start buf))
    (check-equal? (buffer-text deleted) "world"))
  
  (test-case "buffer-select-all"
    (define buf (make-buffer "hello"))
    (define selected (buffer-select-all buf))
    (check-true (buffer-has-selection? selected))
    (check-equal? (buffer-get-selection selected) "hello"))
  
  (test-case "buffer-select-word"
    (define buf (make-buffer "hello world" #:cursor 7))
    (define selected (buffer-select-word buf))
    (check-equal? (buffer-get-selection selected) "world"))
  
  (test-case "buffer-select-to"
    (define buf (make-buffer "hello" #:cursor 1))
    (define selected (buffer-select-to buf 4))
    (check-equal? (buffer-get-selection selected) "ell"))
  
  (test-case "buffer-clear-selection"
    (define buf (buffer-select-all (make-buffer "hello")))
    (define cleared (buffer-clear-selection buf))
    (check-false (buffer-has-selection? cleared)))
  
  (test-case "buffer-delete-selection"
    (define buf (buffer-select-all (make-buffer "hello")))
    (define deleted (buffer-delete-selection buf))
    (check-equal? (buffer-text deleted) "")
    (check-equal? (buffer-cursor deleted) 0))
  
  (test-case "buffer-replace-selection"
    (define buf (text-buffer "hello world" 11 (cons 6 11)))
    (define replaced (buffer-replace-selection buf "there"))
    (check-equal? (buffer-text replaced) "hello there"))
  
  (test-case "buffer-insert clears selection"
    (define buf (buffer-select-all (make-buffer "hello")))
    (define inserted (buffer-insert buf "bye"))
    (check-equal? (buffer-text inserted) "bye")
    (check-false (buffer-has-selection? inserted)))
  
  (test-case "buffer-line-count single line"
    (define buf (make-buffer "hello"))
    (check-equal? (buffer-line-count buf) 1))
  
  (test-case "buffer-line-count multiple lines"
    (define buf (make-buffer "line1\nline2\nline3"))
    (check-equal? (buffer-line-count buf) 3))
  
  (test-case "buffer-current-line"
    (define buf (make-buffer "line1\nline2\nline3" #:cursor 8))
    (check-equal? (buffer-current-line buf) 1))
  
  (test-case "buffer-current-column"
    (define buf (make-buffer "line1\nline2" #:cursor 8))
    (check-equal? (buffer-current-column buf) 2))
  
  (test-case "buffer-length"
    (define buf (make-buffer "hello"))
    (check-equal? (buffer-length buf) 5))
  
  (test-case "empty buffer"
    (check-equal? (buffer-text buffer-empty) "")
    (check-equal? (buffer-cursor buffer-empty) 0)
    (check-false (buffer-has-selection? buffer-empty))))
