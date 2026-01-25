#lang racket/base

(require racket/match
         racket/set
         racket/bytes
         racket/string
         racket/port
         "../event.rkt")

(provide make-input-parser
         parse-input
         parser-pending?
         parser-reset!)

(define ESC 27)
(define CSI-START #"[")

(struct parser ([buffer #:mutable]
                [in-paste? #:mutable]
                [paste-buffer #:mutable])
  #:transparent)

(define (make-input-parser)
  (parser #"" #f #""))

(define (parser-pending? p)
  (> (bytes-length (parser-buffer p)) 0))

(define (parser-reset! p)
  (set-parser-buffer! p #"")
  (set-parser-in-paste?! p #f)
  (set-parser-paste-buffer! p #""))

(define (parse-input p input)
  (define buf (bytes-append (parser-buffer p) 
                            (if (bytes? input) input (string->bytes/utf-8 input))))
  (set-parser-buffer! p buf)
  
  (define events '())
  
  (let loop ()
    (define buf (parser-buffer p))
    (when (> (bytes-length buf) 0)
      (define-values (evt consumed) (try-parse-event p buf))
      (cond
        [(and evt (> consumed 0))
         (set! events (cons evt events))
         (set-parser-buffer! p (subbytes buf consumed))
         (loop)]
        [(and (not evt) (> consumed 0))
         (set-parser-buffer! p (subbytes buf consumed))
         (loop)]
        [else (void)])))
  
  (reverse events))

(define (try-parse-event p buf)
  (define len (bytes-length buf))
  (define b0 (bytes-ref buf 0))
  
  (cond
    [(parser-in-paste? p)
     (parse-paste-content p buf)]
    
    [(= b0 ESC)
     (if (= len 1)
         (values #f 0)
         (parse-escape-sequence p buf))]
    
    [(< b0 32)
     (parse-control-char buf)]
    
    [(= b0 127)
     (values (key-event 'backspace #f (set) (subbytes buf 0 1)) 1)]
    
    [else
     (parse-utf8-char buf)]))

(define (parse-control-char buf)
  (define b (bytes-ref buf 0))
  (define raw (subbytes buf 0 1))
  (define evt
    (match b
      [9  (key-event 'tab #f (set) raw)]
      [10 (key-event 'enter #f (set) raw)]
      [13 (key-event 'enter #f (set) raw)]
      [_  (key-event #f (integer->char (+ b 96)) (set 'ctrl) raw)]))
  (values evt 1))

(define (parse-utf8-char buf)
  (define len (bytes-length buf))
  (define b0 (bytes-ref buf 0))
  (define char-len
    (cond
      [(< b0 #x80) 1]
      [(< b0 #xE0) 2]
      [(< b0 #xF0) 3]
      [else 4]))
  
  (if (< len char-len)
      (values #f 0)
      (let* ([raw (subbytes buf 0 char-len)]
             [s (bytes->string/utf-8 raw #f)]
             [c (and s (> (string-length s) 0) (string-ref s 0))])
        (if c
            (values (key-event (if (char=? c #\space) 'space #f) 
                              c (set) raw) 
                    char-len)
            (values (unknown-event raw) char-len)))))

(define (parse-escape-sequence p buf)
  (define len (bytes-length buf))
  
  (cond
    [(< len 2)
     (values #f 0)]
    
    [(= (bytes-ref buf 1) (char->integer #\[))
     (parse-csi-sequence p buf)]
    
    [(= (bytes-ref buf 1) (char->integer #\O))
     (parse-ss3-sequence buf)]
    
    [else
     (define-values (inner-evt consumed) (try-parse-single-key (subbytes buf 1)))
     (if inner-evt
         (values (key-event (key-event-key inner-evt)
                           (key-event-rune inner-evt)
                           (set-add (key-event-modifiers inner-evt) 'alt)
                           (subbytes buf 0 (add1 consumed)))
                 (add1 consumed))
         (values (key-event 'esc #f (set) (subbytes buf 0 1)) 1))]))

(define (try-parse-single-key buf)
  (if (= (bytes-length buf) 0)
      (values #f 0)
      (let ([b (bytes-ref buf 0)])
        (cond
          [(< b 32)
           (parse-control-char buf)]
          [(< b 127)
           (values (key-event #f (integer->char b) (set) (subbytes buf 0 1)) 1)]
          [else
           (values #f 0)]))))

(define (parse-csi-sequence p buf)
  (define len (bytes-length buf))
  (when (< len 3)
    (values #f 0))
  
  (define end-idx (find-csi-end buf 2))
  (cond
    [(not end-idx)
     (if (> len 20)
         (values (unknown-event buf) len)
         (values #f 0))]
    
    [else
     (define seq (subbytes buf 0 (add1 end-idx)))
     (define final-byte (bytes-ref buf end-idx))
     (define params-str (bytes->string/utf-8 (subbytes buf 2 end-idx)))
     
     (match final-byte
       [(== (char->integer #\A)) (parse-arrow-key seq params-str 'up)]
       [(== (char->integer #\B)) (parse-arrow-key seq params-str 'down)]
       [(== (char->integer #\C)) (parse-arrow-key seq params-str 'right)]
       [(== (char->integer #\D)) (parse-arrow-key seq params-str 'left)]
       [(== (char->integer #\H)) (parse-simple-key seq params-str 'home)]
       [(== (char->integer #\F)) (parse-simple-key seq params-str 'end)]
       [(== (char->integer #\P)) (parse-simple-key seq params-str 'f1)]
       [(== (char->integer #\Q)) (parse-simple-key seq params-str 'f2)]
       [(== (char->integer #\R)) (parse-simple-key seq params-str 'f3)]
       [(== (char->integer #\S)) (parse-simple-key seq params-str 'f4)]
       [(== (char->integer #\Z)) (values (key-event 'tab #f (set 'shift) seq) (add1 end-idx))]
       [(== (char->integer #\~)) (parse-tilde-key p seq params-str)]
       [(== (char->integer #\u)) (parse-kitty-key seq params-str)]
       [(== (char->integer #\M)) (parse-mouse-x10 buf end-idx)]
       [(== (char->integer #\m)) (parse-mouse-sgr seq params-str 'release)]
       [(== (char->integer #\<)) 
        (define sgr-end (find-csi-end buf (add1 end-idx)))
        (if sgr-end
            (parse-mouse-sgr-full buf sgr-end)
            (values #f 0))]
       [(== (char->integer #\I)) (values (focus-event #t) (add1 end-idx))]
       [(== (char->integer #\O)) (values (focus-event #f) (add1 end-idx))]
       [_ (values (unknown-event seq) (add1 end-idx))])]))

(define (find-csi-end buf start)
  (for/first ([i (in-range start (bytes-length buf))]
              #:when (let ([b (bytes-ref buf i)])
                       (and (>= b #x40) (<= b #x7E))))
    i))

(define (parse-arrow-key seq params-str key)
  (define mods (parse-modifier-param params-str))
  (values (key-event key #f mods seq) (bytes-length seq)))

(define (parse-simple-key seq params-str key)
  (define mods (parse-modifier-param params-str))
  (values (key-event key #f mods seq) (bytes-length seq)))

(define (parse-modifier-param params-str)
  (define parts (string-split params-str ";"))
  (if (and (>= (length parts) 2)
           (not (string=? (cadr parts) "")))
      (decode-modifiers (string->number (cadr parts)))
      (set)))

(define (decode-modifiers n)
  (if (not n)
      (set)
      (let ([n (sub1 n)])
        (for/set ([i (in-list '((0 . shift) (1 . alt) (2 . ctrl) (3 . meta)))]
                  #:when (bitwise-bit-set? n (car i)))
          (cdr i)))))

(define (parse-tilde-key p seq params-str)
  (define parts (string-split params-str ";"))
  (define key-num (and (pair? parts) (string->number (car parts))))
  (define mods (if (>= (length parts) 2)
                   (decode-modifiers (string->number (cadr parts)))
                   (set)))
  
  (define key
    (match key-num
      [1 'home]
      [2 'insert]
      [3 'delete]
      [4 'end]
      [5 'page-up]
      [6 'page-down]
      [7 'home]
      [8 'end]
      [11 'f1]
      [12 'f2]
      [13 'f3]
      [14 'f4]
      [15 'f5]
      [17 'f6]
      [18 'f7]
      [19 'f8]
      [20 'f9]
      [21 'f10]
      [23 'f11]
      [24 'f12]
      [200 'paste-start]
      [201 'paste-end]
      [_ #f]))
  
  (cond
    [(eq? key 'paste-start)
     (set-parser-in-paste?! p #t)
     (set-parser-paste-buffer! p #"")
     (values #f (bytes-length seq))]
    [(eq? key 'paste-end)
     (values #f (bytes-length seq))]
    [key
     (values (key-event key #f mods seq) (bytes-length seq))]
    [else
     (values (unknown-event seq) (bytes-length seq))]))

(define (parse-kitty-key seq params-str)
  (define parts (string-split params-str ";"))
  (define keycode (and (pair? parts) (string->number (car parts))))
  (define mods (if (>= (length parts) 2)
                   (let ([mod-part (cadr parts)])
                     (define mod-num (string->number (car (string-split mod-part ":"))))
                     (decode-modifiers mod-num))
                   (set)))
  
  (define-values (key rune)
    (cond
      [(not keycode) (values 'unknown #f)]
      [(= keycode 9) (values 'tab #f)]
      [(= keycode 13) (values 'enter #f)]
      [(= keycode 27) (values 'esc #f)]
      [(= keycode 32) (values 'space #\space)]
      [(= keycode 127) (values 'backspace #f)]
      [(and (>= keycode 1) (<= keycode 26))
       (values #f (integer->char (+ keycode 96)))]
      [(and (>= keycode 32) (<= keycode 126))
       (values #f (integer->char keycode))]
      [(and (>= keycode 57344) (<= keycode 57471))
       (parse-kitty-special-key keycode)]
      [else (values 'unknown #f)]))
  
  (values (key-event key rune mods seq) (bytes-length seq)))

(define (parse-kitty-special-key keycode)
  (match keycode
    [57358 (values 'enter #f)]
    [57359 (values 'tab #f)]
    [57360 (values 'backspace #f)]
    [57361 (values 'insert #f)]
    [57362 (values 'delete #f)]
    [57363 (values 'left #f)]
    [57364 (values 'right #f)]
    [57365 (values 'up #f)]
    [57366 (values 'down #f)]
    [57367 (values 'page-up #f)]
    [57368 (values 'page-down #f)]
    [57369 (values 'home #f)]
    [57370 (values 'end #f)]
    [57376 (values 'f1 #f)]
    [57377 (values 'f2 #f)]
    [57378 (values 'f3 #f)]
    [57379 (values 'f4 #f)]
    [57380 (values 'f5 #f)]
    [57381 (values 'f6 #f)]
    [57382 (values 'f7 #f)]
    [57383 (values 'f8 #f)]
    [57384 (values 'f9 #f)]
    [57385 (values 'f10 #f)]
    [57386 (values 'f11 #f)]
    [57387 (values 'f12 #f)]
    [_ (values 'unknown #f)]))

(define (parse-ss3-sequence buf)
  (define len (bytes-length buf))
  (when (< len 3)
    (values #f 0))
  
  (define final-byte (bytes-ref buf 2))
  (define seq (subbytes buf 0 3))
  
  (define key
    (match final-byte
      [(== (char->integer #\A)) 'up]
      [(== (char->integer #\B)) 'down]
      [(== (char->integer #\C)) 'right]
      [(== (char->integer #\D)) 'left]
      [(== (char->integer #\H)) 'home]
      [(== (char->integer #\F)) 'end]
      [(== (char->integer #\P)) 'f1]
      [(== (char->integer #\Q)) 'f2]
      [(== (char->integer #\R)) 'f3]
      [(== (char->integer #\S)) 'f4]
      [_ #f]))
  
  (if key
      (values (key-event key #f (set) seq) 3)
      (values (unknown-event seq) 3)))

(define (parse-mouse-x10 buf end-idx)
  (define needed (+ end-idx 4))
  (if (< (bytes-length buf) needed)
      (values #f 0)
      (let* ([seq (subbytes buf 0 needed)]
             [cb (- (bytes-ref buf (+ end-idx 1)) 32)]
             [cx (- (bytes-ref buf (+ end-idx 2)) 33)]
             [cy (- (bytes-ref buf (+ end-idx 3)) 33)]
             [button-bits (bitwise-and cb #b11)]
             [motion? (bitwise-bit-set? cb 5)]
             [mods (for/set ([i (in-list '((2 . shift) (3 . alt) (4 . ctrl)))]
                            #:when (bitwise-bit-set? cb (car i)))
                     (cdr i))]
             [button (match button-bits
                       [0 'left]
                       [1 'middle]
                       [2 'right]
                       [3 'none]
                       [_ 'none])]
             [action (cond
                       [motion? 'motion]
                       [(= button-bits 3) 'release]
                       [else 'press])])
        (values (mouse-event cx cy button action mods) needed))))

(define (parse-mouse-sgr seq params-str action)
  (define parts (string-split params-str ";"))
  (if (< (length parts) 3)
      (values (unknown-event seq) (bytes-length seq))
      (let* ([cb (string->number (car parts))]
             [cx (sub1 (or (string->number (cadr parts)) 1))]
             [cy (sub1 (or (string->number (caddr parts)) 1))]
             [button-bits (and cb (bitwise-and cb #b11))]
             [motion? (and cb (bitwise-bit-set? cb 5))]
             [mods (if cb
                       (for/set ([i (in-list '((2 . shift) (3 . alt) (4 . ctrl)))]
                                #:when (bitwise-bit-set? cb (car i)))
                         (cdr i))
                       (set))]
             [button (match button-bits
                       [0 'left]
                       [1 'middle]
                       [2 'right]
                       [64 'scroll-up]
                       [65 'scroll-down]
                       [_ 'none])]
             [final-action (cond
                            [motion? 'motion]
                            [else action])])
        (values (mouse-event cx cy button final-action mods) (bytes-length seq)))))

(define (parse-mouse-sgr-full buf end-idx)
  (define seq (subbytes buf 0 (add1 end-idx)))
  (define final-byte (bytes-ref buf end-idx))
  (define action (if (= final-byte (char->integer #\M)) 'press 'release))
  (define params-str (bytes->string/utf-8 (subbytes buf 3 end-idx)))
  (parse-mouse-sgr seq params-str action))

(define (parse-paste-content p buf)
  (define paste-end-seq #"\e[201~")
  (define end-pos (find-bytes-subsequence buf paste-end-seq))
  
  (if end-pos
      (let ([content (bytes-append (parser-paste-buffer p) (subbytes buf 0 end-pos))])
        (set-parser-in-paste?! p #f)
        (set-parser-paste-buffer! p #"")
        (values (paste-event (bytes->string/utf-8 content #f)) 
                (+ end-pos (bytes-length paste-end-seq))))
      (begin
        (set-parser-paste-buffer! p (bytes-append (parser-paste-buffer p) buf))
        (values #f (bytes-length buf)))))

(define (find-bytes-subsequence haystack needle)
  (define hay-len (bytes-length haystack))
  (define needle-len (bytes-length needle))
  (for/first ([i (in-range (- hay-len needle-len -1))]
              #:when (equal? (subbytes haystack i (+ i needle-len)) needle))
    i))

(module+ test
  (require rackunit)
  
  (define (parse-single input)
    (define p (make-input-parser))
    (define events (parse-input p input))
    (and (pair? events) (car events)))
  
  (test-case "parse simple characters"
    (define evt (parse-single #"a"))
    (check-equal? (key-event-rune evt) #\a)
    (check-false (key-event-key evt)))
  
  (test-case "parse space as symbol"
    (define evt (parse-single #" "))
    (check-eq? (key-event-key evt) 'space)
    (check-equal? (key-event-rune evt) #\space))
  
  (test-case "parse ctrl+c"
    (define evt (parse-single #"\x03"))
    (check-equal? (key-event-rune evt) #\c)
    (check-true (ctrl? evt)))
  
  (test-case "parse enter"
    (define evt (parse-single #"\r"))
    (check-eq? (key-event-key evt) 'enter))
  
  (test-case "parse tab"
    (define evt (parse-single #"\t"))
    (check-eq? (key-event-key evt) 'tab))
  
  (test-case "parse backspace (DEL)"
    (define evt (parse-single #"\x7f"))
    (check-eq? (key-event-key evt) 'backspace))
  
  (test-case "parse arrow keys"
    (check-eq? (key-event-key (parse-single #"\e[A")) 'up)
    (check-eq? (key-event-key (parse-single #"\e[B")) 'down)
    (check-eq? (key-event-key (parse-single #"\e[C")) 'right)
    (check-eq? (key-event-key (parse-single #"\e[D")) 'left))
  
  (test-case "parse arrow with modifiers"
    (define evt (parse-single #"\e[1;5A"))
    (check-eq? (key-event-key evt) 'up)
    (check-true (ctrl? evt)))
  
  (test-case "parse home/end"
    (check-eq? (key-event-key (parse-single #"\e[H")) 'home)
    (check-eq? (key-event-key (parse-single #"\e[F")) 'end)
    (check-eq? (key-event-key (parse-single #"\e[1~")) 'home)
    (check-eq? (key-event-key (parse-single #"\e[4~")) 'end))
  
  (test-case "parse page up/down"
    (check-eq? (key-event-key (parse-single #"\e[5~")) 'page-up)
    (check-eq? (key-event-key (parse-single #"\e[6~")) 'page-down))
  
  (test-case "parse insert/delete"
    (check-eq? (key-event-key (parse-single #"\e[2~")) 'insert)
    (check-eq? (key-event-key (parse-single #"\e[3~")) 'delete))
  
  (test-case "parse function keys"
    (check-eq? (key-event-key (parse-single #"\eOP")) 'f1)
    (check-eq? (key-event-key (parse-single #"\eOQ")) 'f2)
    (check-eq? (key-event-key (parse-single #"\eOR")) 'f3)
    (check-eq? (key-event-key (parse-single #"\eOS")) 'f4)
    (check-eq? (key-event-key (parse-single #"\e[15~")) 'f5)
    (check-eq? (key-event-key (parse-single #"\e[17~")) 'f6)
    (check-eq? (key-event-key (parse-single #"\e[18~")) 'f7)
    (check-eq? (key-event-key (parse-single #"\e[19~")) 'f8)
    (check-eq? (key-event-key (parse-single #"\e[20~")) 'f9)
    (check-eq? (key-event-key (parse-single #"\e[21~")) 'f10)
    (check-eq? (key-event-key (parse-single #"\e[23~")) 'f11)
    (check-eq? (key-event-key (parse-single #"\e[24~")) 'f12))
  
  (test-case "parse alt+key"
    (define evt (parse-single #"\ea"))
    (check-equal? (key-event-rune evt) #\a)
    (check-true (alt? evt)))
  
  (test-case "parse shift+tab"
    (define evt (parse-single #"\e[Z"))
    (check-eq? (key-event-key evt) 'tab)
    (check-true (shift? evt)))
  
  (test-case "parse focus events"
    (check-true (focus-event-focused? (parse-single #"\e[I")))
    (check-false (focus-event-focused? (parse-single #"\e[O"))))
  
  (test-case "parse bracketed paste"
    (define p (make-input-parser))
    (define events (parse-input p #"\e[200~hello world\e[201~"))
    (check-equal? (length events) 1)
    (check-true (paste-event? (car events)))
    (check-equal? (paste-event-text (car events)) "hello world"))
  
  (test-case "parse partial sequence waits"
    (define p (make-input-parser))
    (check-equal? (parse-input p #"\e") '())
    (check-true (parser-pending? p))
    (define events (parse-input p #"[A"))
    (check-equal? (length events) 1)
    (check-eq? (key-event-key (car events)) 'up))
  
  (test-case "parse multiple events"
    (define p (make-input-parser))
    (define events (parse-input p #"ab\e[A"))
    (check-equal? (length events) 3)
    (check-equal? (key-event-rune (car events)) #\a)
    (check-equal? (key-event-rune (cadr events)) #\b)
    (check-eq? (key-event-key (caddr events)) 'up))
  
  (test-case "parse utf8 characters"
    (define evt (parse-single "λ"))
    (check-equal? (key-event-rune evt) #\λ))
  
  (test-case "parse kitty keyboard protocol"
    (define evt (parse-single #"\e[97u"))
    (check-equal? (key-event-rune evt) #\a)
    
    (define evt2 (parse-single #"\e[97;5u"))
    (check-equal? (key-event-rune evt2) #\a)
    (check-true (ctrl? evt2)))
  
  (test-case "parse mouse x10 format"
    (define p (make-input-parser))
    (define events (parse-input p (bytes-append #"\e[M" (bytes 32 43 33))))
    (check-equal? (length events) 1)
    (check-true (mouse-event? (car events)))
    (check-equal? (mouse-event-x (car events)) 10)
    (check-equal? (mouse-event-y (car events)) 0)
    (check-eq? (mouse-event-button (car events)) 'left))
  
  (test-case "parser reset"
    (define p (make-input-parser))
    (parse-input p #"\e")
    (check-true (parser-pending? p))
    (parser-reset! p)
    (check-false (parser-pending? p))))
