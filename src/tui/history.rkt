#lang racket/base

(require (only-in racket/list take first))

(provide (struct-out history-model)
         history-init
         history-prev
         history-next
         history-append
         HISTORY-LIMIT)

(define HISTORY-LIMIT 100)

(struct history-model (past future) #:transparent)

(define (history-init [initial-items '()])
  (define items (if (> (length initial-items) HISTORY-LIMIT)
                    (take initial-items HISTORY-LIMIT)
                    initial-items))
  (history-model (reverse items) '()))

(define (history-prev h current-input)
  (define past (history-model-past h))
  (if (null? past)
      (values h current-input)
      (let ([prev (car past)]
            [rest (cdr past)])
        (values (history-model rest (cons current-input (history-model-future h)))
                prev))))

(define (history-next h current-input)
  (define future (history-model-future h))
  (if (null? future)
      (values h current-input)
      (let ([next (car future)]
            [rest (cdr future)])
        (values (history-model (cons current-input (history-model-past h)) rest)
                next))))

(define (history-append h cmd)
  (define new-past (cons cmd (append (history-model-past h) (reverse (history-model-future h)))))
  (define limited-past (if (> (length new-past) HISTORY-LIMIT)
                           (take new-past HISTORY-LIMIT)
                           new-past))
  (history-model limited-past '()))

(module+ test
  (require rackunit)

  (test-case "history-init creates empty history"
    (define h (history-init))
    (check-equal? (history-model-past h) '())
    (check-equal? (history-model-future h) '()))

  (test-case "history-init with initial items"
    (define h (history-init '("a" "b" "c")))
    (check-equal? (history-model-past h) '("c" "b" "a")))

  (test-case "history-prev navigates backward"
    (define h (history-init '("a" "b" "c")))
    (define-values (h1 val1) (history-prev h "current"))
    (check-equal? val1 "c")
    (define-values (h2 val2) (history-prev h1 val1))
    (check-equal? val2 "b")
    (define-values (h3 val3) (history-prev h2 val2))
    (check-equal? val3 "a"))

  (test-case "history-prev at beginning stays put"
    (define h (history-init '("only")))
    (define-values (h1 val1) (history-prev h "current"))
    (check-equal? val1 "only")
    (define-values (h2 val2) (history-prev h1 val1))
    (check-equal? val2 "only"))

  (test-case "history-next navigates forward"
    (define h (history-init '("a" "b" "c")))
    (define-values (h1 _) (history-prev h "current"))
    (define-values (h2 _2) (history-prev h1 "c"))
    (define-values (h3 val) (history-next h2 "b"))
    (check-equal? val "c"))

  (test-case "history-next at end stays put"
    (define h (history-init '("a")))
    (define-values (h1 val) (history-next h "current"))
    (check-equal? val "current"))

  (test-case "history-append adds command"
    (define h (history-init '("a")))
    (define h1 (history-append h "b"))
    (check-equal? (history-model-past h1) '("b" "a")))

  (test-case "history respects HISTORY-LIMIT"
    (define big-list (for/list ([i (in-range 150)]) (format "cmd-~a" i)))
    (define h (history-init big-list))
    (check-equal? (length (history-model-past h)) HISTORY-LIMIT))

  (test-case "history-append enforces limit"
    (define big-list (for/list ([i (in-range 100)]) (format "cmd-~a" i)))
    (define h (history-init big-list))
    (define h1 (history-append h "new-cmd"))
    (check-equal? (length (history-model-past h1)) HISTORY-LIMIT)
    (check-equal? (first (history-model-past h1)) "new-cmd")))
