#lang racket/gui

(require racket/class
         "theme-system.rkt")

(provide styled-button%
         styled-text-field%
         styled-choice%
         styled-panel%
         styled-message%
         make-styled-button
         make-styled-text-field
         apply-theme!)

;; ============================================================================
;; Styled Button - Canvas-based with hover/click animations
;; ============================================================================

(define styled-button%
  (class canvas%
    (init parent label [callback (λ () (void))])
    (init-field [min-width 80] [min-height 32])
    
    (define btn-label label)
    (define btn-callback callback)
    (define hover? #f)
    (define pressed? #f)
    
    (super-new [parent parent]
               [min-width min-width]
               [min-height min-height]
               [style '(border)])
    
    (define/override (on-paint)
      (define dc (send this get-dc))
      (define-values (w h) (send this get-size))
      (define bg-color
        (cond [pressed? (theme-ref 'accent)]
              [hover? (theme-ref 'button-hover)]
              [else (theme-ref 'button-bg)]))
      (define fg-color
        (if pressed?
            (theme-ref 'bg)
            (theme-ref 'fg)))
      (send dc set-brush bg-color 'solid)
      (send dc set-pen (theme-ref 'border) 1 'solid)
      (send dc draw-rounded-rectangle 0 0 w h 4)
      (send dc set-text-foreground fg-color)
      (send dc set-font (make-font #:size 10 #:family 'default))
      (define-values (tw th _d _s) (send dc get-text-extent btn-label))
      (send dc draw-text btn-label (/ (- w tw) 2) (/ (- h th) 2)))
    
    (define/override (on-event evt)
      (define type (send evt get-event-type))
      (case type
        [(enter)
         (set! hover? #t)
         (send this refresh)]
        [(leave)
         (set! hover? #f)
         (set! pressed? #f)
         (send this refresh)]
        [(left-down)
         (set! pressed? #t)
         (send this refresh)]
        [(left-up)
         (when pressed?
           (set! pressed? #f)
           (send this refresh)
           (btn-callback))]))
    
    (define/public (set-label! new-label)
      (set! btn-label new-label)
      (send this refresh))
    
    (define/public (refresh-theme!)
      (send this refresh))))

;; ============================================================================
;; Styled Text Field - With placeholder support
;; ============================================================================

(define styled-text-field%
  (class text-field%
    (init parent [label #f] [placeholder ""])
    (init-field [init-value ""])
    
    (define placeholder-text placeholder)
    (define showing-placeholder? #t)
    
    (super-new [parent parent]
               [label label]
               [init-value (if (string=? init-value "") placeholder init-value)])
    
    (define editor (send this get-editor))
    
    (define (update-placeholder-style!)
      (define text (send editor get-text))
      (cond
        [(and showing-placeholder? (string=? text placeholder-text))
         (send editor change-style
               (make-object style-delta% 'change-italic)
               0 (string-length placeholder-text))]
        [else
         (send editor change-style
               (make-object style-delta% 'change-normal)
               0 (send editor last-position))]))
    
    (define/override (on-focus on?)
      (define text (send editor get-text))
      (cond
        [(and on? showing-placeholder? (string=? text placeholder-text))
         (send editor erase)
         (set! showing-placeholder? #f)]
        [(and (not on?) (string=? (string-trim text) ""))
         (send editor insert placeholder-text)
         (set! showing-placeholder? #t)
         (update-placeholder-style!)])
      (super on-focus on?))
    
    (define/public (get-real-value)
      (define text (send editor get-text))
      (if (and showing-placeholder? (string=? text placeholder-text))
          ""
          text))
    
    (define/public (set-placeholder! new-placeholder)
      (when (and showing-placeholder? 
                 (string=? (send editor get-text) placeholder-text))
        (send editor erase)
        (send editor insert new-placeholder))
      (set! placeholder-text new-placeholder)
      (update-placeholder-style!))
    
    (define/public (refresh-theme!)
      (void))
    
    (when (string=? init-value "")
      (update-placeholder-style!))))

;; ============================================================================
;; Styled Choice - Themed dropdown
;; ============================================================================

(define styled-choice%
  (class choice%
    (init parent label choices [callback (λ (c e) (void))])
    
    (super-new [parent parent]
               [label label]
               [choices choices]
               [callback callback])
    
    (define/public (refresh-theme!)
      (void))))

;; ============================================================================
;; Styled Panel - With themed background
;; ============================================================================

(define styled-panel%
  (class panel%
    (init parent)
    (init-field [surface-key 'surface])
    
    (super-new [parent parent])
    
    (define/public (refresh-theme!)
      (send this set-canvas-background (theme-ref surface-key)))
    
    (send this refresh-theme!)))

;; ============================================================================
;; Styled Message - Themed label
;; ============================================================================

(define styled-message%
  (class message%
    (init parent label)
    
    (super-new [parent parent]
               [label label])
    
    (define/public (refresh-theme!)
      (void))))

;; ============================================================================
;; Factory Functions
;; ============================================================================

(define (make-styled-button parent label callback
                            #:min-width [min-width 80]
                            #:min-height [min-height 32])
  (new styled-button%
       [parent parent]
       [label label]
       [callback callback]
       [min-width min-width]
       [min-height min-height]))

(define (make-styled-text-field parent
                                #:label [label #f]
                                #:placeholder [placeholder ""]
                                #:init-value [init-value ""])
  (new styled-text-field%
       [parent parent]
       [label label]
       [placeholder placeholder]
       [init-value init-value]))

;; ============================================================================
;; Theme Application
;; ============================================================================

(define (apply-theme! widget)
  (when (is-a? widget styled-button%)
    (send widget refresh-theme!))
  (when (is-a? widget styled-text-field%)
    (send widget refresh-theme!))
  (when (is-a? widget styled-choice%)
    (send widget refresh-theme!))
  (when (is-a? widget styled-panel%)
    (send widget refresh-theme!))
  (when (is-a? widget styled-message%)
    (send widget refresh-theme!))
  (when (and (is-a? widget area-container<%>)
             (method-in-interface? 'get-children (object-interface widget)))
    (for ([child (send widget get-children)])
      (apply-theme! child))))
