#lang racket/base
;; Command Queue System
;; Allows users to queue tasks for the agent to process after completing current work.

(provide add-to-queue!
         get-next-queued!
         list-queue!
         clear-queue!
         queue-length
         peek-queue
         remove-queue-item!
         MAX-QUEUE)

(require racket/list 
         racket/string)

(define queue-store (box '()))
(define MAX-QUEUE 20)

(define (add-to-queue! task)
  (define trimmed (string-trim task))
  (if (or (string=? trimmed "") 
          (>= (length (unbox queue-store)) MAX-QUEUE))
      #f
      (begin
        (set-box! queue-store (append (unbox queue-store) (list trimmed)))
        #t)))

(define (get-next-queued!)
  (define q (unbox queue-store))
  (if (null? q)
      #f
      (begin
        (set-box! queue-store (cdr q))
        (car q))))

(define (list-queue!)
  (unbox queue-store))

(define (clear-queue!)
  (set-box! queue-store '()))

(define (queue-length)
  (length (unbox queue-store)))

;; Extra utilities
(define (peek-queue)
  (define q (unbox queue-store))
  (if (null? q) #f (car q)))

(define (remove-queue-item! index)
  (define q (unbox queue-store))
  (if (and (>= index 0) (< index (length q)))
      (begin
        (set-box! queue-store 
                  (append (take q index) (drop q (add1 index))))
        #t)
      #f))

(module+ test
  (require rackunit)
  
  (test-case "queue operations"
    (clear-queue!)
    (check-equal? (queue-length) 0)
    (check-true (add-to-queue! "task 1"))
    (check-equal? (queue-length) 1)
    (check-equal? (peek-queue) "task 1")
    (check-true (add-to-queue! "task 2"))
    (check-equal? (queue-length) 2)
    
    (define tasks (list-queue!))
    (check-equal? tasks '("task 1" "task 2"))
    
    (check-equal? (get-next-queued!) "task 1")
    (check-equal? (queue-length) 1)
    
    (clear-queue!)
    (check-equal? (queue-length) 0)))
