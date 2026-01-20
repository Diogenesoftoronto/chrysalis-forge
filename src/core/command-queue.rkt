#lang racket/base
;; Command Queue System
;; Allows users to queue tasks for the agent to process after completing current work.

(provide add-to-queue!
         get-next-queued!
         peek-queue
         list-queue
         clear-queue!
         remove-queue-item!
         queue-empty?
         queue-length
         command-queue-param)

(require racket/list)

(define command-queue-param (make-parameter '()))
(define MAX-QUEUE 20)

(define (add-to-queue! task)
  (define trimmed (string-trim task))
  (when (> (string-length trimmed) 0)
    (define current (command-queue-param))
    (if (>= (length current) MAX-QUEUE)
        #f
        (begin
          (command-queue-param (append current (list trimmed)))
          #t))))

(define (get-next-queued!)
  (define current (command-queue-param))
  (if (null? current)
      #f
      (let ([task (first current)])
        (command-queue-param (rest current))
        task)))

(define (peek-queue)
  (define current (command-queue-param))
  (if (null? current) #f (first current)))

(define (list-queue)
  (command-queue-param))

(define (clear-queue!)
  (command-queue-param '()))

(define (remove-queue-item! index)
  (define current (command-queue-param))
  (if (and (>= index 0) (< index (length current)))
      (begin
        (command-queue-param (append (take current index) (drop current (add1 index))))
        #t)
      #f))

(define (queue-empty?)
  (null? (command-queue-param)))

(define (queue-length)
  (length (command-queue-param)))

(define (string-trim str)
  (regexp-replace* #px"^\\s+|\\s+$" str ""))

(module+ test
  (require rackunit)
  
  (test-case "queue operations"
    (parameterize ([command-queue-param '()])
      (check-true (queue-empty?))
      (check-true (add-to-queue! "task 1"))
      (check-false (queue-empty?))
      (check-equal? (queue-length) 1)
      (check-equal? (peek-queue) "task 1")
      (check-true (add-to-queue! "task 2"))
      (check-equal? (queue-length) 2)
      (check-equal? (get-next-queued!) "task 1")
      (check-equal? (queue-length) 1)
      (clear-queue!)
      (check-true (queue-empty?)))))
