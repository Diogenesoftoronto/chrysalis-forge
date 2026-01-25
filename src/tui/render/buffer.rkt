#lang racket/base
(provide (struct-out render-buffer)
         make-render-buffer
         buffer-width
         buffer-height
         buffer-set!
         buffer-get
         buffer-fill!
         buffer-blit!
         buffer-overlay!
         buffer-to-string
         transparent-cell?)

(require racket/match
         racket/string
         racket/format
         "../style.rkt"
         "../text/measure.rkt")

;; ============================================================================
;; Buffer Cell
;; ============================================================================

(struct buffer-cell (char style transparent?) #:transparent)

(define empty-buffer-cell
  (buffer-cell #\space empty-style #f))

(define transparent-marker
  (buffer-cell #\nul #f #t))

(define (transparent-cell? c)
  (and (buffer-cell? c) (buffer-cell-transparent? c)))

;; ============================================================================
;; Render Buffer
;; ============================================================================

(struct render-buffer (width height cells) #:mutable #:transparent)

(define (make-render-buffer width height [fill-char #\space] [fill-style #f])
  (define initial-cell (buffer-cell fill-char (or fill-style empty-style) #f))
  (define cells
    (for/vector ([_ (in-range height)])
      (make-vector width initial-cell)))
  (render-buffer width height cells))

(define (buffer-width buf)
  (render-buffer-width buf))

(define (buffer-height buf)
  (render-buffer-height buf))

;; ============================================================================
;; Buffer Operations
;; ============================================================================

(define (buffer-set! buf x y char [st #f] #:transparent? [transparent? #f])
  (when (and (>= x 0) (< x (buffer-width buf))
             (>= y 0) (< y (buffer-height buf)))
    (define row (vector-ref (render-buffer-cells buf) y))
    (define c (if (string? char)
                  (if (> (string-length char) 0)
                      (string-ref char 0)
                      #\space)
                  char))
    (vector-set! row x (buffer-cell c (or st empty-style) transparent?))))

(define (buffer-get buf x y)
  (if (and (>= x 0) (< x (buffer-width buf))
           (>= y 0) (< y (buffer-height buf)))
      (vector-ref (vector-ref (render-buffer-cells buf) y) x)
      empty-buffer-cell))

(define (buffer-fill! buf x y w h char [st #f])
  (define c (if (string? char)
                (if (> (string-length char) 0)
                    (string-ref char 0)
                    #\space)
                char))
  (define cell (buffer-cell c (or st empty-style) #f))
  (for* ([row (in-range y (min (+ y h) (buffer-height buf)))]
         [col (in-range x (min (+ x w) (buffer-width buf)))])
    (when (and (>= row 0) (>= col 0))
      (vector-set! (vector-ref (render-buffer-cells buf) row) col cell))))

(define (buffer-blit! dst src dst-x dst-y [src-x 0] [src-y 0] [w #f] [h #f])
  (define actual-w (or w (buffer-width src)))
  (define actual-h (or h (buffer-height src)))
  
  (for* ([sy (in-range src-y (min (+ src-y actual-h) (buffer-height src)))]
         [sx (in-range src-x (min (+ src-x actual-w) (buffer-width src)))])
    (define dx (+ dst-x (- sx src-x)))
    (define dy (+ dst-y (- sy src-y)))
    (when (and (>= dx 0) (< dx (buffer-width dst))
               (>= dy 0) (< dy (buffer-height dst)))
      (define cell (buffer-get src sx sy))
      (vector-set! (vector-ref (render-buffer-cells dst) dy) dx cell))))

(define (buffer-overlay! dst src dst-x dst-y)
  (define w (buffer-width src))
  (define h (buffer-height src))
  
  (for* ([sy (in-range h)]
         [sx (in-range w)])
    (define dx (+ dst-x sx))
    (define dy (+ dst-y sy))
    (when (and (>= dx 0) (< dx (buffer-width dst))
               (>= dy 0) (< dy (buffer-height dst)))
      (define src-cell (buffer-get src sx sy))
      (unless (transparent-cell? src-cell)
        (vector-set! (vector-ref (render-buffer-cells dst) dy) dx src-cell)))))

;; ============================================================================
;; String Conversion
;; ============================================================================

(define (style->ansi-codes st)
  (if (not st)
      ""
      (string-append
       (color->ansi-fg (style-fg st))
       (color->ansi-bg (style-bg st))
       (if (style-bold st) "\e[1m" "")
       (if (style-dim st) "\e[2m" "")
       (if (style-italic st) "\e[3m" "")
       (if (style-underline st) "\e[4m" "")
       (if (style-blink st) "\e[5m" "")
       (if (style-reverse st) "\e[7m" "")
       (if (style-strikethrough st) "\e[9m" ""))))

(define (styles-equal? a b)
  (or (and (not a) (not b))
      (and a b
           (equal? (style-fg a) (style-fg b))
           (equal? (style-bg a) (style-bg b))
           (equal? (style-bold a) (style-bold b))
           (equal? (style-dim a) (style-dim b))
           (equal? (style-italic a) (style-italic b))
           (equal? (style-underline a) (style-underline b))
           (equal? (style-strikethrough a) (style-strikethrough b))
           (equal? (style-blink a) (style-blink b))
           (equal? (style-reverse a) (style-reverse b)))))

(define (buffer-to-string buf)
  (define lines
    (for/list ([row (in-range (buffer-height buf))])
      (define row-vec (vector-ref (render-buffer-cells buf) row))
      (define out (open-output-string))
      (define current-style #f)
      
      (for ([col (in-range (buffer-width buf))])
        (define cell (vector-ref row-vec col))
        (define st (buffer-cell-style cell))
        (define ch (buffer-cell-char cell))
        
        (unless (styles-equal? current-style st)
          (when current-style
            (display "\e[0m" out))
          (define codes (style->ansi-codes st))
          (when (non-empty-string? codes)
            (display codes out))
          (set! current-style st))
        
        (display (if (transparent-cell? cell) #\space ch) out))
      
      (when current-style
        (display "\e[0m" out))
      
      (get-output-string out)))
  
  (string-join lines "\n"))

;; ============================================================================
;; Tests
;; ============================================================================

(module+ test
  (require rackunit)
  
  (test-case "make-render-buffer creates correct dimensions"
    (define buf (make-render-buffer 10 5))
    (check-equal? (buffer-width buf) 10)
    (check-equal? (buffer-height buf) 5))
  
  (test-case "buffer-set! and buffer-get work"
    (define buf (make-render-buffer 10 10))
    (buffer-set! buf 5 5 #\X)
    (define cell (buffer-get buf 5 5))
    (check-equal? (buffer-cell-char cell) #\X))
  
  (test-case "buffer-set! handles strings"
    (define buf (make-render-buffer 10 10))
    (buffer-set! buf 0 0 "A")
    (check-equal? (buffer-cell-char (buffer-get buf 0 0)) #\A))
  
  (test-case "buffer-set! ignores out of bounds"
    (define buf (make-render-buffer 5 5))
    (buffer-set! buf -1 0 #\X)
    (buffer-set! buf 0 -1 #\X)
    (buffer-set! buf 10 0 #\X)
    (buffer-set! buf 0 10 #\X)
    (check-equal? (buffer-cell-char (buffer-get buf 0 0)) #\space))
  
  (test-case "buffer-get returns empty for out of bounds"
    (define buf (make-render-buffer 5 5))
    (define cell (buffer-get buf -1 0))
    (check-equal? (buffer-cell-char cell) #\space))
  
  (test-case "buffer-fill! fills region"
    (define buf (make-render-buffer 10 10))
    (buffer-fill! buf 2 2 3 3 #\#)
    (check-equal? (buffer-cell-char (buffer-get buf 2 2)) #\#)
    (check-equal? (buffer-cell-char (buffer-get buf 4 4)) #\#)
    (check-equal? (buffer-cell-char (buffer-get buf 1 1)) #\space)
    (check-equal? (buffer-cell-char (buffer-get buf 5 5)) #\space))
  
  (test-case "buffer-blit! copies region"
    (define src (make-render-buffer 5 5))
    (define dst (make-render-buffer 10 10))
    (buffer-fill! src 0 0 5 5 #\X)
    (buffer-blit! dst src 2 2)
    (check-equal? (buffer-cell-char (buffer-get dst 2 2)) #\X)
    (check-equal? (buffer-cell-char (buffer-get dst 6 6)) #\X)
    (check-equal? (buffer-cell-char (buffer-get dst 0 0)) #\space))
  
  (test-case "buffer-blit! with partial region"
    (define src (make-render-buffer 10 10))
    (define dst (make-render-buffer 10 10))
    (buffer-fill! src 0 0 10 10 #\X)
    (buffer-blit! dst src 0 0 2 2 3 3)
    (check-equal? (buffer-cell-char (buffer-get dst 0 0)) #\X)
    (check-equal? (buffer-cell-char (buffer-get dst 2 2)) #\X)
    (check-equal? (buffer-cell-char (buffer-get dst 3 3)) #\space))
  
  (test-case "buffer-overlay! respects transparency"
    (define bg (make-render-buffer 5 5))
    (define fg (make-render-buffer 5 5))
    (buffer-fill! bg 0 0 5 5 #\.)
    (buffer-set! fg 0 0 #\X)
    (buffer-set! fg 1 0 #\Y #f #:transparent? #t)
    (buffer-overlay! bg fg 0 0)
    (check-equal? (buffer-cell-char (buffer-get bg 0 0)) #\X)
    (check-equal? (buffer-cell-char (buffer-get bg 1 0)) #\.))
  
  (test-case "transparent-cell? detects transparent cells"
    (define buf (make-render-buffer 5 5))
    (buffer-set! buf 0 0 #\X #f #:transparent? #t)
    (buffer-set! buf 1 0 #\Y)
    (check-true (transparent-cell? (buffer-get buf 0 0)))
    (check-false (transparent-cell? (buffer-get buf 1 0))))
  
  (test-case "buffer-to-string produces output"
    (define buf (make-render-buffer 3 2))
    (buffer-set! buf 0 0 #\a)
    (buffer-set! buf 1 0 #\b)
    (buffer-set! buf 2 0 #\c)
    (buffer-set! buf 0 1 #\d)
    (buffer-set! buf 1 1 #\e)
    (buffer-set! buf 2 1 #\f)
    (define result (buffer-to-string buf))
    (check-true (string-contains? result "abc"))
    (check-true (string-contains? result "def")))
  
  (test-case "buffer-to-string with styled content"
    (define buf (make-render-buffer 3 1))
    (define st (style-set empty-style #:fg 'red))
    (buffer-set! buf 0 0 #\X st)
    (buffer-set! buf 1 0 #\Y st)
    (buffer-set! buf 2 0 #\Z st)
    (define result (buffer-to-string buf))
    (check-true (string-contains? result "\e["))
    (check-true (string-contains? result "XYZ"))))
