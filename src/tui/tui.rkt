#lang racket/base
;; TUI Framework - Main Export Module
;; Bubble Tea-style Elm architecture with Lipgloss-like styling for Racket
;;
;; Usage:
;;   (require "tui/tui.rkt")
;;   (run-program #:init my-init #:update my-update #:view my-view)

(require
 "terminal.rkt"
 "program.rkt"
 "event.rkt"
 "keymap.rkt"
 "style.rkt"
 "doc.rkt"
 "layout.rkt"
 "text/measure.rkt"
 "text/buffer.rkt"
 "widgets/text-input.rkt"
 "widgets/textarea.rkt"
 "widgets/viewport.rkt"
 "widgets/list.rkt"
 "render/screen.rkt"
 "render/buffer.rkt")

;; Re-export with conflict resolution (prefer the original defining module)
(provide
 ;; Terminal control
 (all-from-out "terminal.rkt")
 
 ;; Program runner (Bubble Tea core)
 (all-from-out "program.rkt")
 
 ;; Events (canonical source)
 (all-from-out "event.rkt")
 
 ;; Keymap (except key-event which comes from event.rkt)
 (except-out (all-from-out "keymap.rkt")
             key-event key-event? key-event-key key-event-rune 
             key-event-modifiers key-event-raw)
 
 ;; Styling
 (all-from-out "style.rkt")
 
 ;; Document representation
 (all-from-out "doc.rkt")
 
 ;; Layout engine (except rect which comes from program.rkt)
 (except-out (all-from-out "layout.rkt") rect rect? rect-x rect-y rect-width rect-height)
 
 ;; Text measurement
 (all-from-out "text/measure.rkt")
 
 ;; Text buffer
 (all-from-out "text/buffer.rkt")
 
 ;; Widgets
 (all-from-out "widgets/text-input.rkt")
 (all-from-out "widgets/textarea.rkt")
 (all-from-out "widgets/viewport.rkt")
 (all-from-out "widgets/list.rkt")
 
 ;; Rendering
 (all-from-out "render/screen.rkt")
 (all-from-out "render/buffer.rkt"))

;; ============================================================================
;; Quick-start helpers
;; ============================================================================

(provide
 define-tui-app
 simple-app)

;; Convenience macro for defining a TUI application
(define-syntax-rule (define-tui-app name init-expr update-expr view-expr)
  (define name
    (program init-expr update-expr view-expr (λ (_) '()) (hash))))

;; Create a simple interactive app with common defaults
(define (simple-app #:init init
                    #:update update
                    #:view view
                    #:title [title #f]
                    #:fps [fps 30])
  (run-program #:init init
               #:update update
               #:view view
               #:options (hash 'title title 'fps fps)))
