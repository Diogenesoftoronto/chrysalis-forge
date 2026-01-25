#lang racket/base

(require racket/match
         racket/string
         racket/list
         racket/format
         "../doc.rkt"
         "../style.rkt")

(provide ansi-string->doc)

;; Map ANSI SGR codes to style actions
(define (apply-sgr code input-style)
  (cond
    [(not code) input-style] ; Empty code (e.g. \e[m) resets
    [(or (= code 0)) empty-style]
    [(= code 1) (style-set input-style #:bold #t)]
    [(= code 2) (style-set input-style #:dim #t)]
    [(= code 3) (style-set input-style #:italic #t)]
    [(= code 4) (style-set input-style #:underline #t)]
    [(= code 5) (style-set input-style #:blink #t)]
    [(= code 7) (style-set input-style #:reverse #t)]
    [(= code 9) (style-set input-style #:strikethrough #t)]
    ;; Foreground 30-37
    [(and (>= code 30) (<= code 37))
     (style-set input-style #:fg (case code
                                   [(30) 'black] [(31) 'red] [(32) 'green]
                                   [(33) 'yellow] [(34) 'blue] [(35) 'magenta]
                                   [(36) 'cyan] [(37) 'white]))]
    ;; Background 40-47
    [(and (>= code 40) (<= code 47))
     (style-set input-style #:bg (case code
                                   [(40) 'black] [(41) 'red] [(42) 'green]
                                   [(43) 'yellow] [(44) 'blue] [(45) 'magenta]
                                   [(46) 'cyan] [(47) 'white]))]
    ;; Bright Foreground 90-97
    [(and (>= code 90) (<= code 97))
     (style-set input-style #:fg (case code
                                   [(90) 'bright-black] [(91) 'bright-red]
                                   [(92) 'bright-green] [(93) 'bright-yellow]
                                   [(94) 'bright-blue] [(95) 'bright-magenta]
                                   [(96) 'bright-cyan] [(97) 'bright-white]))]
    ;; Bright Background 100-107
    [(and (>= code 100) (<= code 107))
     (style-set input-style #:bg (case code
                                   [(100) 'bright-black] [(101) 'bright-red]
                                   [(102) 'bright-green] [(103) 'bright-yellow]
                                   [(104) 'bright-blue] [(105) 'bright-magenta]
                                   [(106) 'bright-cyan] [(107) 'bright-white]))]
    
    ;; TODO: Support 256/TrueColor (38/48) which requires lookahead
    ;; For now, we assume simple SGR codes.
    [else input-style]))

(define (apply-sgr-sequence codes current-style)
  (cond
    [(empty? codes) current-style]
    [else
     (define code (first codes))
     (cond
       ;; Foreground 256 colors: 38;5;n
       [(and (= code 38) (>= (length codes) 3) (= (second codes) 5))
        (apply-sgr-sequence (drop codes 3)
                            (style-set current-style #:fg (third codes)))]
       
       ;; Foreground TrueColor: 38;2;r;g;b
       [(and (= code 38) (>= (length codes) 5) (= (second codes) 2))
        (match-define (list _ _ r g b) (take codes 5))
        (define (to-hex n) (~r n #:base 16 #:min-width 2 #:pad-string "0"))
        (define hex (string-append "#" (to-hex r) (to-hex g) (to-hex b)))
        (apply-sgr-sequence (drop codes 5)
                            (style-set current-style #:fg hex))]
       
       ;; Background 256 colors: 48;5;n
       [(and (= code 48) (>= (length codes) 3) (= (second codes) 5))
        (apply-sgr-sequence (drop codes 3)
                            (style-set current-style #:bg (third codes)))]
       
       ;; Background TrueColor: 48;2;r;g;b
       [(and (= code 48) (>= (length codes) 5) (= (second codes) 2))
        (match-define (list _ _ r g b) (take codes 5))
        (define (to-hex n) (~r n #:base 16 #:min-width 2 #:pad-string "0"))
        (define hex (string-append "#" (to-hex r) (to-hex g) (to-hex b)))
        (apply-sgr-sequence (drop codes 5)
                            (style-set current-style #:bg hex))]
       
       ;; Standard codes
       [else
        (apply-sgr-sequence (rest codes) (apply-sgr code current-style))])]))

(define (ansi-string->doc str [current-style empty-style])
  (define pattern #rx"\e\\[([0-9;]*)m")
  (define parts (regexp-match-positions* pattern str))
  
  (cond
    [(empty? parts) (txt str current-style)]
    [else
     (define chunks
       (let loop ([tokens parts]
                  [last-idx 0]
                  [cur-style current-style]
                  [acc '()])
         (cond
           [(empty? tokens)
            (if (< last-idx (string-length str))
                (cons (txt (substring str last-idx) cur-style) acc)
                acc)]
           [else
            (match-define (cons start end) (first tokens))
            ;; Text before the code
            (define pre-text (substring str last-idx start))
            (define new-acc (if (non-empty-string? pre-text)
                                (cons (txt pre-text cur-style) acc)
                                acc))
            ;; Parse code
            (define code-str (substring str (+ start 2) (sub1 end)))
            (define codes
              (if (equal? code-str "")
                  '(0)
                  (map string->number (string-split code-str ";"))))
            
            (define next-style (apply-sgr-sequence codes cur-style))
                
            (loop (rest tokens) end next-style new-acc)])))
     
     (hjoin (reverse chunks))]))

(module+ test
  (require rackunit)
  
  (test-case "ansi parser basic color"
    (define d (ansi-string->doc "\e[31mRed\e[0m"))
    (check-true (doc-row? d))
    (define children (doc-row-children d))
    (check-equal? (length children) 1)
    (check-equal? (doc-text-content (first children)) "Red")
    (check-eq? (style-fg (doc-text-style (first children))) 'red))

  (test-case "ansi parser 256 color"
    (define d (ansi-string->doc "\e[38;5;196mRed\e[0m"))
    (define children (doc-row-children d))
    (check-equal? (style-fg (doc-text-style (first children))) 196))

  (test-case "ansi parser truecolor"
    (define d (ansi-string->doc "\e[38;2;255;0;0mRed\e[0m"))
    (define children (doc-row-children d))
    (check-equal? (style-fg (doc-text-style (first children))) "#ff0000"))
  
  (test-case "ansi parser mixed codes"
    (define d (ansi-string->doc "\e[1;38;5;196mBoldRed\e[0m"))
    (define children (doc-row-children d))
    (check-true (style-bold (doc-text-style (first children))))
    (check-equal? (style-fg (doc-text-style (first children))) 196))
)
