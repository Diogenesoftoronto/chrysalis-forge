#lang racket/base

(require racket/match
         racket/list
         racket/string
         "../doc.rkt"
         "../style.rkt"
         "../event.rkt"
         "text-input.rkt")

(provide (struct-out palette-model)
         palette-init
         palette-update
         palette-view
         palette-show
         palette-hide)

(struct palette-model (visible? input items filtered-items selected-index callback) #:transparent)

(define (fuzzy-match? query item)
  (define q-chars (string->list (string-downcase query)))
  (define i-chars (string->list (string-downcase item)))
  (let loop ([qs q-chars] [is i-chars])
    (cond
      [(null? qs) #t]
      [(null? is) #f]
      [(char=? (car qs) (car is)) (loop (cdr qs) (cdr is))]
      [else (loop qs (cdr is))])))

(define (fuzzy-score query item)
  (define q (string-downcase query))
  (define i (string-downcase item))
  (cond
    [(string-prefix? i q) 100]
    [(string-contains? i q) 50]
    [(fuzzy-match? query item) 25]
    [else 0]))

(define (filter-items query items)
  (if (equal? query "")
      items
      (let* ([scored (map (λ (i) (cons (fuzzy-score query i) i)) items)]
             [filtered (filter (λ (p) (> (car p) 0)) scored)]
             [sorted (sort filtered > #:key car)])
        (map cdr sorted))))

(define (palette-init items [callback void])
  (palette-model #f
                 (text-input-init)
                 items
                 items ; filtered
                 0
                 callback))

(define (palette-show model)
  (struct-copy palette-model model
               [visible? #t]
               [input (text-input-init)]
               [filtered-items (palette-model-items model)]
               [selected-index 0]))

(define (palette-hide model)
  (struct-copy palette-model model [visible? #f]))

(define (palette-update model evt)
  (if (not (palette-model-visible? model))
      (values model '())
      (match evt
        ;; Navigation
        [(key-event 'up _ _ _)
         (define idx (palette-model-selected-index model))
         (values (struct-copy palette-model model [selected-index (max 0 (sub1 idx))])
                 '())]

        [(key-event 'down _ _ _)
         (define idx (palette-model-selected-index model))
         (define max-idx (sub1 (length (palette-model-filtered-items model))))
         (values (struct-copy palette-model model [selected-index (min max-idx (add1 idx))])
                 '())]

        ;; Selection
        [(key-event 'enter _ _ _)
         (define items (palette-model-filtered-items model))
         (define idx (palette-model-selected-index model))
         (if (and (>= idx 0) (< idx (length items)))
             (values (palette-hide model)
                     (list (list 'palette-select (list-ref items idx))))
             (values model '()))]

        ;; Cancel
        [(key-event 'escape _ _ _)
         (values (palette-hide model) '())]

        ;; Input
        [_
         (define-values (new-input input-cmd) (text-input-update (palette-model-input model) evt))
         (define new-visible? (palette-model-visible? model)) ;; Keep visible
         ;; Update filter
         (define query (text-input-value new-input))
         (define new-items (filter-items query (palette-model-items model)))
         (define new-idx (min 0 (sub1 (length new-items)))) ;; Reset selection? Or keep 0.

         (values (struct-copy palette-model model
                              [input new-input]
                              [filtered-items new-items]
                              [selected-index 0]) ; Always reset to top on filter change
                 input-cmd)])))

(define (palette-view model width)
  (if (not (palette-model-visible? model))
      (doc-empty)
      (let ()
        (define w (min 60 (- width 4)))
        (define h 15)

        (define input-box
          (box (text-input-view (palette-model-input model) (- w 2))
               (style-set empty-style #:border 'rounded #:width w #:border-fg 'cyan)))

        (define items (palette-model-filtered-items model))
        (define list-content
          (cond
            [(empty? items) (txt "No matching commands" (style-set empty-style #:fg 'bright-black))]
            [else
             (vjoin
              (for/list ([item (in-list (take items (min (length items) 10)))] ;; Show top 10
                         [i (in-naturals)])
                (define selected? (= i (palette-model-selected-index model)))
                (define st (if selected?
                               (style-set empty-style #:bg 'blue #:fg 'white)
                               empty-style))
                (txt (format " ~a " item) (style-set st #:width (- w 2)))))
             ]))

        (define list-box
          (box list-content
               (style-set empty-style #:border 'rounded #:width w #:border-fg 'bright-black #:border-style 'rounded)))

        ;; Overlay logic usually handled by layout engine 'overlay' node.
        ;; But here we return a document that IS the palette.
        ;; The caller should wrap it in overlay or place it.
        (vjoin (list input-box list-box) (style-set empty-style #:align 'center)))))
