#lang racket/base
;; TUI Framework Demo - Showcases the Bubble Tea-style architecture
;;
;; Run with: racket src/tui/examples/demo.rkt

(require "../tui.rkt"
         racket/match
         racket/set)

;; ============================================================================
;; Model
;; ============================================================================

(struct app-model (input list-widget viewport counter quit?) #:transparent)

;; ============================================================================
;; Messages
;; ============================================================================

(struct increment-msg () #:transparent)
(struct decrement-msg () #:transparent)
(struct submit-msg (text) #:transparent)

;; ============================================================================
;; Init
;; ============================================================================

(define (init)
  (define input-model
    (text-input-init #:placeholder "Type something..."
                     #:prompt "Input: "))
  
  (define list-model
    (list-init #:items (list (list-item "Option 1" "opt1" #t (hash))
                             (list-item "Option 2" "opt2" #t (hash))
                             (list-item "Option 3" "opt3" #t (hash))
                             (list-item "Disabled" "dis" #f (hash)))
               #:height 5))
  
  (define viewport-model
    (viewport-init #:width 40 #:height 8
                   #:content "Welcome to the TUI demo!\n\nThis framework provides:\n• Elm-style architecture\n• Lipgloss-style styling\n• Rich text input widgets\n• Flexbox-like layouts\n• Efficient diff rendering\n\nScroll with arrows or j/k."))
  
  (values (app-model input-model list-model viewport-model 0 #f)
          none))

;; ============================================================================
;; Update
;; ============================================================================

(define (update model msg)
  (match msg
    [(key-event 'esc _ _ _)
     (values (struct-copy app-model model [quit? #t]) (quit))]
    
    [(key-event #f #\q (? (λ (m) (set-member? m 'ctrl))) _)
     (values (struct-copy app-model model [quit? #t]) (quit))]
    
    [(increment-msg)
     (values (struct-copy app-model model
                          [counter (add1 (app-model-counter model))])
             none)]
    
    [(decrement-msg)
     (values (struct-copy app-model model
                          [counter (sub1 (app-model-counter model))])
             none)]
    
    [(submit-msg text)
     (displayln (format "Submitted: ~a" text))
     (values model none)]
    
    [_
     (values model none)]))

;; ============================================================================
;; View
;; ============================================================================

(define header-style
  (style-set empty-style
             #:fg 'cyan
             #:bold #t))

(define box-style
  (style-set empty-style
             #:border rounded-border
             #:border-fg 'magenta
             #:padding '(0 1 0 1)))

(define counter-style
  (style-set empty-style
             #:fg 'yellow
             #:bold #t))

(define (view model size)
  (define w (size-width size))
  (define h (size-height size))
  
  (col
   ;; Header
   (doc-block
    (txt "╔═══ TUI Framework Demo ═══╗" header-style)
    empty-style)
   
   (vspace 1)
   
   ;; Main content in a row
   (row
    ;; Left column: Input and counter
    (col
     (doc-block
      (col
       (txt "Text Input" header-style)
       (vspace 1)
       (text-input-view (app-model-input model) 30))
      box-style)
     
     (vspace 1)
     
     (doc-block
      (col
       (txt "Counter" header-style)
       (txt (format "Value: ~a" (app-model-counter model)) counter-style)
       (txt "Press +/- to change"))
      box-style))
    
    (hspace 2)
    
    ;; Right column: List and viewport
    (col
     (doc-block
      (col
       (txt "Selection List" header-style)
       (vspace 1)
       (list-view (app-model-list-widget model)))
      box-style)
     
     (vspace 1)
     
     (doc-block
      (col
       (txt "Scrollable Viewport" header-style)
       (vspace 1)
       (viewport-view (app-model-viewport model)))
      box-style)))
   
   (vspace 1)
   
   ;; Footer
   (txt "Press ESC or Ctrl+Q to quit | +/- for counter | Arrows to navigate"
        (style-set empty-style #:fg 'white #:dim #t))))

;; ============================================================================
;; Main
;; ============================================================================

(module+ main
  (displayln "Starting TUI demo... (Press ESC to quit)")
  (displayln "Note: This is a demo of the API. Full interactive mode requires terminal setup.")
  (displayln "")
  
  ;; Show what the view would render at 80x24
  (define-values (model _) (init))
  (define output (render (view model (size 80 24)) 80 24))
  (displayln output)
  
  (displayln "")
  (displayln "To run interactively, use run-program:")
  (displayln "  (run-program #:init init #:update update #:view view)"))
