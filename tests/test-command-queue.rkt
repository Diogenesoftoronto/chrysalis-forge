#lang racket/base
(require rackunit
         "../src/core/command-queue.rkt")

(test-case "Command Queue System"
  (printf "Testing Command Queue...\n")
  
  (clear-queue!)
  (check-equal? (queue-length) 0 "Queue starts empty")
  (check-equal? (list-queue!) '() "List queue returns empty list")
  
  (check-true (add-to-queue! "task 1") "Can add task 1")
  (check-equal? (queue-length) 1 "Queue length is 1")
  (check-equal? (peek-queue) "task 1" "Peek returns task 1")
  
  (check-true (add-to-queue! "task 2") "Can add task 2")
  (check-equal? (queue-length) 2 "Queue length is 2")
  (check-equal? (list-queue!) '("task 1" "task 2") "List returns correct tasks")
  
  ;; Test limit
  (clear-queue!)
  (for ([i (in-range 20)])
    (check-true (add-to-queue! (format "task ~a" i))))
  (check-equal? (queue-length) 20 "Queue filled to max")
  (check-false (add-to-queue! "overflow") "Cannot add past limit")
  
  ;; Test processing
  (clear-queue!)
  (add-to-queue! "t1")
  (add-to-queue! "t2")
  (check-equal? (get-next-queued!) "t1" "Get next returns first added")
  (check-equal? (queue-length) 1 "Queue shrinks")
  (check-equal? (get-next-queued!) "t2" "Get next returns second added")
  (check-equal? (queue-length) 0 "Queue empty")
  (check-false (get-next-queued!) "Get next on empty returns #f")
  
  ;; Test remove item
  (clear-queue!)
  (add-to-queue! "A")
  (add-to-queue! "B")
  (add-to-queue! "C")
  (check-true (remove-queue-item! 1) "Remove middle item")
  (check-equal? (list-queue!) '("A" "C") "Queue has correct items")
  
  (displayln "Command Queue Tests Passed!")
)
