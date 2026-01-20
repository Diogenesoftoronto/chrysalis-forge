#lang racket/gui

(require racket/class)

(provide animation-manager%
         make-animation-manager
         animate!
         ease-linear
         ease-in-quad
         ease-out-quad
         ease-in-out-quad
         ease-in-cubic
         ease-out-cubic
         ease-in-out-cubic)

;; Easing functions: t in [0,1] -> [0,1]

(define (ease-linear t) t)

(define (ease-in-quad t) (* t t))

(define (ease-out-quad t) (- 1 (* (- 1 t) (- 1 t))))

(define (ease-in-out-quad t)
  (if (< t 0.5)
      (* 2 t t)
      (- 1 (/ (expt (+ (* -2 t) 2) 2) 2))))

(define (ease-in-cubic t) (* t t t))

(define (ease-out-cubic t) (- 1 (expt (- 1 t) 3)))

(define (ease-in-out-cubic t)
  (if (< t 0.5)
      (* 4 t t t)
      (- 1 (/ (expt (+ (* -2 t) 2) 3) 2))))

;; Easing name lookup
(define (get-easing-fn name)
  (case name
    [(linear) ease-linear]
    [(ease-in ease-in-quad) ease-in-quad]
    [(ease-out ease-out-quad) ease-out-quad]
    [(ease-in-out ease-in-out-quad) ease-in-out-quad]
    [(ease-in-cubic) ease-in-cubic]
    [(ease-out-cubic) ease-out-cubic]
    [(ease-in-out-cubic) ease-in-out-cubic]
    [else ease-linear]))

;; Animation struct
(struct animation
  (id target property from to duration-ms easing-fn callback start-time)
  #:mutable)

;; Animation Manager Class
(define animation-manager%
  (class object%
    (super-new)
    
    (define animations (make-hash))
    (define next-id 0)
    (define timer #f)
    (define frame-interval (/ 1000.0 60.0)) ; ~16.67ms for 60fps
    
    (define/public (start-animation target property from to duration-ms easing callback)
      (define id next-id)
      (set! next-id (add1 next-id))
      (define easing-fn (if (procedure? easing) easing (get-easing-fn easing)))
      (define anim (animation id target property from to duration-ms easing-fn callback (current-inexact-milliseconds)))
      (hash-set! animations id anim)
      (ensure-timer-running!)
      id)
    
    (define/public (stop-animation animation-id)
      (hash-remove! animations animation-id)
      (maybe-stop-timer!))
    
    (define/public (stop-all)
      (hash-clear! animations)
      (maybe-stop-timer!))
    
    (define/public (animation-count)
      (hash-count animations))
    
    (define/private (ensure-timer-running!)
      (unless timer
        (set! timer (new timer%
                         [notify-callback (λ () (tick!))]
                         [interval (inexact->exact (round frame-interval))]
                         [just-once? #f]))))
    
    (define/private (maybe-stop-timer!)
      (when (and timer (hash-empty? animations))
        (send timer stop)
        (set! timer #f)))
    
    (define/private (tick!)
      (define now (current-inexact-milliseconds))
      (define completed '())
      
      (for ([(id anim) (in-hash animations)])
        (define elapsed (- now (animation-start-time anim)))
        (define duration (animation-duration-ms anim))
        (define progress (min 1.0 (/ elapsed duration)))
        (define eased ((animation-easing-fn anim) progress))
        (define from (animation-from anim))
        (define to (animation-to anim))
        (define current-value (+ from (* eased (- to from))))
        
        ;; Apply value to target
        (define target (animation-target anim))
        (define prop (animation-property anim))
        (apply-property! target prop current-value)
        
        (when (>= progress 1.0)
          (set! completed (cons anim completed))))
      
      ;; Handle completed animations
      (for ([anim (in-list completed)])
        (hash-remove! animations (animation-id anim))
        (define cb (animation-callback anim))
        (when cb (cb)))
      
      (maybe-stop-timer!))
    
    (define/private (apply-property! target prop value)
      (cond
        [(and (is-a? target window<%>) (eq? prop 'width))
         (define h (send target get-height))
         (send target resize (inexact->exact (round value)) h)]
        [(and (is-a? target window<%>) (eq? prop 'height))
         (define w (send target get-width))
         (send target resize w (inexact->exact (round value)))]
        [(and (is-a? target window<%>) (eq? prop 'x))
         (define-values (_ y) (send target get-position))
         (send target move (inexact->exact (round value)) y)]
        [(and (is-a? target window<%>) (eq? prop 'y))
         (define-values (x _) (send target get-position))
         (send target move x (inexact->exact (round value)))]
        [(hash? target)
         (hash-set! target prop value)]
        [(box? target)
         (set-box! target value)]
        [else (void)]))))

;; Convenience constructor
(define (make-animation-manager)
  (new animation-manager%))

;; Convenience animation function
(define (animate! manager target prop from to
                  #:duration [duration 300]
                  #:easing [easing 'ease-out]
                  #:on-complete [on-complete #f])
  (send manager start-animation target prop from to duration easing on-complete))
