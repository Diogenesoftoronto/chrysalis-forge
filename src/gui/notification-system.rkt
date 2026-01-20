#lang racket/gui

(require racket/class
         "theme-system.rkt")

(provide notification-manager%
         make-notification-manager
         show-notification!)

;; ============================================================================
;; Constants
;; ============================================================================

(define DEFAULT-DURATION 3000)
(define TOAST-WIDTH 300)
(define TOAST-HEIGHT 60)
(define TOAST-MARGIN 10)
(define SLIDE-STEP 10)
(define ANIMATION-INTERVAL 16)

;; Type icons and color keys
(define notification-types
  (hasheq 'info    (cons "ℹ" 'info)
          'success (cons "✓" 'success)
          'warning (cons "⚠" 'warning)
          'error   (cons "✗" 'error)))

;; ============================================================================
;; Toast Canvas
;; ============================================================================

(define toast-canvas%
  (class canvas%
    (init-field type message on-dismiss)
    
    (super-new [style '(transparent)])
    
    (define icon-text (car (hash-ref notification-types type (cons "ℹ" 'info))))
    (define color-key (cdr (hash-ref notification-types type (cons "ℹ" 'info))))
    
    (define/override (on-paint)
      (define dc (send this get-dc))
      (define-values (w h) (send this get-size))
      
      ;; Background
      (define bg-color (theme-ref 'surface))
      (define border-color (theme-ref color-key))
      (define fg-color (theme-ref 'fg))
      
      (send dc set-brush bg-color 'solid)
      (send dc set-pen border-color 2 'solid)
      (send dc draw-rounded-rectangle 0 0 w h 8)
      
      ;; Icon
      (send dc set-font (make-font #:size 18 #:weight 'bold))
      (send dc set-text-foreground border-color)
      (send dc draw-text icon-text 12 (/ (- h 20) 2))
      
      ;; Message
      (send dc set-font (make-font #:size 11))
      (send dc set-text-foreground fg-color)
      (send dc draw-text message 40 (/ (- h 14) 2)))
    
    (define/override (on-event evt)
      (when (eq? (send evt get-event-type) 'left-down)
        (on-dismiss)))))

;; ============================================================================
;; Notification Manager Class
;; ============================================================================

(define notification-manager%
  (class object%
    (init-field parent)
    
    (super-new)
    
    (define queue '())
    (define active-toasts '())
    (define toast-container #f)
    
    ;; Initialize container frame
    (define/private (ensure-container!)
      (unless toast-container
        (set! toast-container
              (new frame%
                   [label ""]
                   [style '(no-caption no-resize-border float)]
                   [width TOAST-WIDTH]
                   [height 1]))))
    
    ;; Position container at top-right of parent
    (define/private (position-container!)
      (ensure-container!)
      (define-values (px py) (send parent get-position))
      (define-values (pw _ph) (send parent get-size))
      (define x (- (+ px pw) TOAST-WIDTH TOAST-MARGIN))
      (define y (+ py TOAST-MARGIN))
      (send toast-container move x y))
    
    ;; Update container height based on active toasts
    (define/private (update-container-height!)
      (define total-height
        (+ (* (length active-toasts) (+ TOAST-HEIGHT TOAST-MARGIN))
           TOAST-MARGIN))
      (send toast-container resize TOAST-WIDTH (max 1 total-height)))
    
    ;; Create a toast entry
    (define/private (create-toast type message duration)
      (ensure-container!)
      (position-container!)
      
      (define panel (new vertical-panel%
                         [parent toast-container]
                         [min-width TOAST-WIDTH]
                         [min-height TOAST-HEIGHT]
                         [stretchable-height #f]))
      
      (define toast-entry (mcons panel #f)) ; (panel . timer)
      
      (define canvas
        (new toast-canvas%
             [parent panel]
             [type type]
             [message message]
             [min-width TOAST-WIDTH]
             [min-height TOAST-HEIGHT]
             [on-dismiss (λ () (dismiss-toast! toast-entry))]))
      
      ;; Auto-dismiss timer
      (define timer
        (new timer%
             [notify-callback (λ () (dismiss-toast! toast-entry))]
             [interval duration]
             [just-once? #t]))
      
      (set-mcdr! toast-entry timer)
      (set! active-toasts (append active-toasts (list toast-entry)))
      (update-container-height!)
      (send toast-container show #t))
    
    ;; Dismiss a specific toast
    (define/private (dismiss-toast! toast-entry)
      (define panel (mcar toast-entry))
      (define timer (mcdr toast-entry))
      
      (when timer (send timer stop))
      (send panel show #f)
      (send toast-container delete-child panel)
      
      (set! active-toasts (remove toast-entry active-toasts))
      (update-container-height!)
      
      (when (null? active-toasts)
        (send toast-container show #f))
      
      ;; Process queue
      (process-queue!))
    
    ;; Process notification queue
    (define/private (process-queue!)
      (when (and (not (null? queue))
                 (< (length active-toasts) 5))
        (define next (car queue))
        (set! queue (cdr queue))
        (create-toast (first next) (second next) (third next))))
    
    ;; Public: Show a toast notification
    (define/public (show-toast type message [duration DEFAULT-DURATION])
      (if (< (length active-toasts) 5)
          (send this do-create-toast type message duration)
          (set! queue (append queue (list (list type message duration))))))
    
    ;; Internal method wrapper for create-toast
    (define/private (do-create-toast type message duration)
      (create-toast type message duration))
    
    ;; Public: Dismiss all notifications
    (define/public (dismiss-all)
      (set! queue '())
      (for ([entry (in-list active-toasts)])
        (define panel (mcar entry))
        (define timer (mcdr entry))
        (when timer (send timer stop))
        (send panel show #f)
        (send toast-container delete-child panel))
      (set! active-toasts '())
      (when toast-container
        (send toast-container show #f)))))

;; ============================================================================
;; Convenience Functions
;; ============================================================================

(define (make-notification-manager parent)
  (new notification-manager% [parent parent]))

(define (show-notification! manager type message #:duration [duration DEFAULT-DURATION])
  (send manager show-toast type message duration))
