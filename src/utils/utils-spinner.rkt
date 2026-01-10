#lang racket/base
(provide start-spinner! stop-spinner!)
(require racket/port racket/list)

(define SPINNER-FRAMES '("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏"))

(define (start-spinner! [label "Thinking..."])
  (define out (current-error-port))
  (thread
   (λ ()
     (let loop ([frames SPINNER-FRAMES])
       (define frame (if (null? frames) (first SPINNER-FRAMES) (first frames)))
       (define next-frames (if (null? frames) (rest SPINNER-FRAMES) (rest frames)))
       
       ;; Clear line, print frame and label
       (fprintf out "\r\033[K~a ~a" frame label)
       (flush-output out)
       
       (sleep 0.1)
       (loop (if (null? next-frames) SPINNER-FRAMES next-frames))))))

(define (stop-spinner! t)
  (when (thread? t)
    (kill-thread t)
    (define out (current-error-port))
    ;; Clear the line one last time
    (fprintf out "\r\033[K")
    (flush-output out)))
