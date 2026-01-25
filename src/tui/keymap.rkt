#lang racket/base

(require racket/match
         racket/list
         racket/string
         racket/contract
         racket/set
         "event.rkt")

(provide
 ;; Re-export key-event from event.rkt for convenience
 (struct-out key-event)
 key-event->keychord

 ;; Key chord representation
 (struct-out keychord)
 make-keychord
 keychord-equal?

 ;; Key sequence (multiple chords)
 (struct-out keyseq)
 make-keyseq
 keyseq-length
 keyseq-prefix?

 ;; Binding
 (struct-out binding)
 make-binding

 ;; Keymap operations
 make-keymap
 keymap?
 keymap-bind
 keymap-unbind
 keymap-merge
 keymap-lookup
 keymap-bindings
 dispatch-key

 ;; Key sequence state
 (struct-out keyseq-state)
 make-keyseq-state
 keyseq-state-pending?
 keyseq-state-feed
 keyseq-state-reset
 keyseq-state-timeout?

 ;; Convenience
 kbd
 define-keys

 ;; Built-in keymaps
 default-keymap
 emacs-keymap)

;; ============================================================================
;; Helper to create key events (uses event.rkt's key-event)
;; ============================================================================

(define (make-key-event* #:key [key #f] #:rune [rune #f] #:modifiers [mods '()])
  (key-event key rune (list->set (or mods '())) #""))

;; ============================================================================
;; Key Chord (single key with modifiers)
;; ============================================================================

(struct keychord (key rune modifiers)
  #:transparent
  #:guard (λ (key rune mods name)
            (values key rune (sort (or mods '()) symbol<?))))

(define (make-keychord #:key [key #f] #:rune [rune #f] #:modifiers [mods '()])
  (keychord key rune (sort (or mods '()) symbol<?)))

(define (keychord-equal? a b)
  (and (equal? (keychord-key a) (keychord-key b))
       (equal? (keychord-rune a) (keychord-rune b))
       (equal? (keychord-modifiers a) (keychord-modifiers b))))

(define (key-event->keychord evt)
  (define mods (key-event-modifiers evt))
  (make-keychord #:key (key-event-key evt)
                 #:rune (key-event-rune evt)
                 #:modifiers (if (set? mods) (set->list mods) (or mods '()))))

;; ============================================================================
;; Key Sequence (list of chords for multi-key bindings)
;; ============================================================================

(struct keyseq (chords)
  #:transparent)

(define (make-keyseq chords)
  (keyseq (if (list? chords) chords (list chords))))

(define (keyseq-length ks)
  (length (keyseq-chords ks)))

(define (keyseq-prefix? prefix full)
  (define prefix-chords (keyseq-chords prefix))
  (define full-chords (keyseq-chords full))
  (and (<= (length prefix-chords) (length full-chords))
       (for/and ([p (in-list prefix-chords)]
                 [f (in-list full-chords)])
         (keychord-equal? p f))))

(define (keyseq-equal? a b)
  (and (= (keyseq-length a) (keyseq-length b))
       (for/and ([ac (in-list (keyseq-chords a))]
                 [bc (in-list (keyseq-chords b))])
         (keychord-equal? ac bc))))

;; ============================================================================
;; Binding
;; ============================================================================

(struct binding (keyseq handler doc when-pred)
  #:transparent)

(define (make-binding ks handler #:doc [doc ""] #:when [when-pred (λ (_) #t)])
  (binding (if (keyseq? ks) ks (make-keyseq (list ks)))
           handler
           doc
           when-pred))

;; ============================================================================
;; Keymap
;; ============================================================================

(struct keymap (bindings-hash)
  #:transparent)

(define (make-keymap)
  (keymap (hash)))

(define (keyseq->key ks)
  (keyseq-chords ks))

(define (keymap-bind km ks handler #:doc [doc ""] #:when [when-pred (λ (_) #t)])
  (define seq (if (keyseq? ks) ks (make-keyseq (list ks))))
  (define b (make-binding seq handler #:doc doc #:when when-pred))
  (keymap (hash-set (keymap-bindings-hash km)
                    (keyseq->key seq)
                    b)))

(define (keymap-unbind km ks)
  (define seq (if (keyseq? ks) ks (make-keyseq (list ks))))
  (keymap (hash-remove (keymap-bindings-hash km) (keyseq->key seq))))

(define (keymap-merge base overlay)
  (keymap (for/fold ([h (keymap-bindings-hash base)])
                    ([(k v) (in-hash (keymap-bindings-hash overlay))])
            (hash-set h k v))))

(define (keymap-bindings km)
  (hash-values (keymap-bindings-hash km)))

(define (keymap-lookup km ks [context #f])
  (define seq (if (keyseq? ks) ks (make-keyseq (list ks))))
  (define key (keyseq->key seq))
  (define b (hash-ref (keymap-bindings-hash km) key #f))
  (and b
       ((binding-when-pred b) context)
       b))

(define (keymap-has-prefix? km partial-chords)
  (for/or ([(key _) (in-hash (keymap-bindings-hash km))])
    (and (> (length key) (length partial-chords))
         (for/and ([p (in-list partial-chords)]
                   [k (in-list key)])
           (keychord-equal? p k)))))

;; ============================================================================
;; Key Sequence State (for tracking partial sequences)
;; ============================================================================

(struct keyseq-state (pending-chords last-time timeout-ms)
  #:transparent)

(define (make-keyseq-state #:timeout-ms [timeout 1000])
  (keyseq-state '() #f timeout))

(define (keyseq-state-pending? st)
  (not (null? (keyseq-state-pending-chords st))))

(define (keyseq-state-timeout? st [current-time-ms (current-inexact-milliseconds)])
  (define last (keyseq-state-last-time st))
  (and last
       (keyseq-state-pending? st)
       (> (- current-time-ms last) (keyseq-state-timeout-ms st))))

(define (keyseq-state-reset st)
  (struct-copy keyseq-state st
               [pending-chords '()]
               [last-time #f]))

(define (keyseq-state-feed st chord)
  (struct-copy keyseq-state st
               [pending-chords (append (keyseq-state-pending-chords st) (list chord))]
               [last-time (current-inexact-milliseconds)]))

;; ============================================================================
;; Dispatch
;; ============================================================================

(struct dispatch-result (match? state model cmds)
  #:transparent)

(define (dispatch-key km st key-evt model [context #f])
  (define now (current-inexact-milliseconds))

  (define st* (if (keyseq-state-timeout? st now)
                  (keyseq-state-reset st)
                  st))

  (define chord (key-event->keychord key-evt))
  (define pending (append (keyseq-state-pending-chords st*) (list chord)))
  (define seq (make-keyseq pending))

  (define b (keymap-lookup km seq context))

  (cond
    [b
     (define result ((binding-handler b) model key-evt))
     (define-values (new-model cmds)
       (if (and (list? result) (= (length result) 2))
           (values (first result) (second result))
           (values result '())))
     (dispatch-result #t (keyseq-state-reset st*) new-model cmds)]

    [(keymap-has-prefix? km pending)
     (dispatch-result #f
                      (struct-copy keyseq-state st*
                                   [pending-chords pending]
                                   [last-time now])
                      model
                      '())]

    [(> (length pending) 1)
     (dispatch-key km (keyseq-state-reset st*) key-evt model context)]

    [else
     (dispatch-result #f (keyseq-state-reset st*) model '())]))

;; ============================================================================
;; kbd - Key Description Parser
;; ============================================================================

(define modifier-prefixes
  '(("C-" . ctrl)
    ("M-" . alt)
    ("A-" . alt)
    ("S-" . shift)
    ("s-" . super)
    ("H-" . hyper)))

(define special-key-names
  (hash
   "enter"     'enter
   "return"    'enter
   "ret"       'enter
   "tab"       'tab
   "space"     'space
   "spc"       'space
   "backspace" 'backspace
   "bksp"      'backspace
   "delete"    'delete
   "del"       'delete
   "escape"    'escape
   "esc"       'escape
   "up"        'up
   "down"      'down
   "left"      'left
   "right"     'right
   "home"      'home
   "end"       'end
   "pageup"    'page-up
   "pgup"      'page-up
   "pagedown"  'page-down
   "pgdn"      'page-down
   "insert"    'insert
   "ins"       'insert
   "f1"        'f1
   "f2"        'f2
   "f3"        'f3
   "f4"        'f4
   "f5"        'f5
   "f6"        'f6
   "f7"        'f7
   "f8"        'f8
   "f9"        'f9
   "f10"       'f10
   "f11"       'f11
   "f12"       'f12))

(define (parse-single-key str)
  (define mods '())
  (define remaining str)

  (let loop ()
    (define found
      (for/first ([mp (in-list modifier-prefixes)]
                  #:when (string-prefix? remaining (car mp)))
        mp))
    (when found
      (set! mods (cons (cdr found) mods))
      (set! remaining (substring remaining (string-length (car found))))
      (loop)))

  (define key-part (string-downcase remaining))

  (cond
    [(hash-has-key? special-key-names key-part)
     (make-keychord #:key (hash-ref special-key-names key-part)
                    #:modifiers (reverse mods))]
    [(= (string-length remaining) 1)
     (make-keychord #:rune (string-ref remaining 0)
                    #:modifiers (reverse mods))]
    [else
     (error 'kbd "Unknown key: ~a" remaining)]))

(define (kbd str)
  (define parts (string-split str))
  (make-keyseq (map parse-single-key parts)))

;; ============================================================================
;; define-keys Macro
;; ============================================================================

(require (for-syntax racket/base syntax/parse))

(define-syntax (define-keys stx)
  (syntax-parse stx
    [(_ km-expr:expr [key-str:str handler-expr:expr (~optional (~seq #:doc doc-expr:expr) #:defaults ([doc-expr #'""])) (~optional (~seq #:when when-expr:expr) #:defaults ([when-expr #'(λ (_) #t)]))] ...)
     #'(let ([km km-expr])
         (foldl (λ (proc acc) (proc acc))
                km
                (list (λ (k) (keymap-bind k (kbd key-str) handler-expr #:doc doc-expr #:when when-expr)) ...)))]))

;; ============================================================================
;; Built-in Keymaps
;; ============================================================================

(define (noop-handler model evt)
  (values model '()))

(define (msg-handler msg)
  (λ (model evt) (values model (list msg))))

(define default-keymap
  (define-keys (make-keymap)
    ["up"       (msg-handler 'cursor-up)    #:doc "Move cursor up"]
    ["down"     (msg-handler 'cursor-down)  #:doc "Move cursor down"]
    ["left"     (msg-handler 'cursor-left)  #:doc "Move cursor left"]
    ["right"    (msg-handler 'cursor-right) #:doc "Move cursor right"]
    ["home"     (msg-handler 'cursor-home)  #:doc "Move to beginning of line"]
    ["end"      (msg-handler 'cursor-end)   #:doc "Move to end of line"]
    ["pageup"   (msg-handler 'page-up)      #:doc "Page up"]
    ["pagedown" (msg-handler 'page-down)    #:doc "Page down"]
    ["enter"    (msg-handler 'submit)       #:doc "Submit/confirm"]
    ["escape"   (msg-handler 'cancel)       #:doc "Cancel/escape"]
    ["tab"      (msg-handler 'next-field)   #:doc "Next field"]
    ["S-tab"    (msg-handler 'prev-field)   #:doc "Previous field"]
    ["backspace" (msg-handler 'delete-back) #:doc "Delete character before cursor"]
    ["delete"   (msg-handler 'delete-forward) #:doc "Delete character at cursor"]))

(define emacs-keymap
  (define-keys (make-keymap)
    ["C-a"   (msg-handler 'cursor-home)      #:doc "Beginning of line"]
    ["C-e"   (msg-handler 'cursor-end)       #:doc "End of line"]
    ["C-f"   (msg-handler 'cursor-right)     #:doc "Forward character"]
    ["C-b"   (msg-handler 'cursor-left)      #:doc "Backward character"]
    ["C-p"   (msg-handler 'cursor-up)        #:doc "Previous line"]
    ["C-n"   (msg-handler 'cursor-down)      #:doc "Next line"]
    ["C-d"   (msg-handler 'delete-forward)   #:doc "Delete forward"]
    ["C-h"   (msg-handler 'delete-back)      #:doc "Delete backward"]
    ["C-k"   (msg-handler 'kill-line)        #:doc "Kill to end of line"]
    ["C-y"   (msg-handler 'yank)             #:doc "Yank (paste)"]
    ["C-w"   (msg-handler 'kill-region)      #:doc "Kill region"]
    ["M-w"   (msg-handler 'copy-region)      #:doc "Copy region"]
    ["C-g"   (msg-handler 'cancel)           #:doc "Cancel"]
    ["C-v"   (msg-handler 'page-down)        #:doc "Page down"]
    ["M-v"   (msg-handler 'page-up)          #:doc "Page up"]
    ["M-f"   (msg-handler 'forward-word)     #:doc "Forward word"]
    ["M-b"   (msg-handler 'backward-word)    #:doc "Backward word"]
    ["M-d"   (msg-handler 'kill-word)        #:doc "Kill word forward"]
    ["M-<"   (msg-handler 'buffer-start)     #:doc "Beginning of buffer"]
    ["M->"   (msg-handler 'buffer-end)       #:doc "End of buffer"]
    ["C-x C-s" (msg-handler 'save)           #:doc "Save"]
    ["C-x C-c" (msg-handler 'quit)           #:doc "Quit"]
    ["C-x k"   (msg-handler 'kill-buffer)    #:doc "Kill buffer"]
    ["C-x o"   (msg-handler 'other-window)   #:doc "Other window"]))

;; ============================================================================
;; Tests
;; ============================================================================

(module+ test
  (require rackunit)

  ;; kbd parsing tests
  (test-case "kbd parses single character"
    (define ks (kbd "a"))
    (check-equal? (keyseq-length ks) 1)
    (define chord (first (keyseq-chords ks)))
    (check-equal? (keychord-rune chord) #\a)
    (check-equal? (keychord-modifiers chord) '()))

  (test-case "kbd parses ctrl modifier"
    (define ks (kbd "C-x"))
    (define chord (first (keyseq-chords ks)))
    (check-equal? (keychord-rune chord) #\x)
    (check-equal? (keychord-modifiers chord) '(ctrl)))

  (test-case "kbd parses multiple modifiers"
    (define ks (kbd "C-M-x"))
    (define chord (first (keyseq-chords ks)))
    (check-equal? (keychord-rune chord) #\x)
    (check-equal? (keychord-modifiers chord) '(alt ctrl)))

  (test-case "kbd parses special keys"
    (define ks (kbd "enter"))
    (define chord (first (keyseq-chords ks)))
    (check-equal? (keychord-key chord) 'enter))

  (test-case "kbd parses key sequences"
    (define ks (kbd "C-x C-s"))
    (check-equal? (keyseq-length ks) 2)
    (define c1 (first (keyseq-chords ks)))
    (define c2 (second (keyseq-chords ks)))
    (check-equal? (keychord-rune c1) #\x)
    (check-equal? (keychord-modifiers c1) '(ctrl))
    (check-equal? (keychord-rune c2) #\s)
    (check-equal? (keychord-modifiers c2) '(ctrl)))

  (test-case "kbd parses g g sequence"
    (define ks (kbd "g g"))
    (check-equal? (keyseq-length ks) 2)
    (check-equal? (keychord-rune (first (keyseq-chords ks))) #\g)
    (check-equal? (keychord-rune (second (keyseq-chords ks))) #\g))

  (test-case "kbd parses shift modifier"
    (define ks (kbd "S-tab"))
    (define chord (first (keyseq-chords ks)))
    (check-equal? (keychord-key chord) 'tab)
    (check-equal? (keychord-modifiers chord) '(shift)))

  ;; Keymap tests
  (test-case "keymap-bind and keymap-lookup"
    (define km (keymap-bind (make-keymap) (kbd "C-s") (λ (m e) m) #:doc "save"))
    (define b (keymap-lookup km (kbd "C-s")))
    (check-not-false b)
    (check-equal? (binding-doc b) "save"))

  (test-case "keymap-lookup returns #f for unbound"
    (define km (make-keymap))
    (check-false (keymap-lookup km (kbd "C-z"))))

  (test-case "keymap-merge overlays bindings"
    (define base (keymap-bind (make-keymap) (kbd "a") (λ (m e) 'base)))
    (define overlay (keymap-bind (make-keymap) (kbd "a") (λ (m e) 'overlay)))
    (define merged (keymap-merge base overlay))
    (define b (keymap-lookup merged (kbd "a")))
    (check-equal? ((binding-handler b) #f #f) 'overlay))

  (test-case "keymap-unbind removes binding"
    (define km (keymap-bind (make-keymap) (kbd "C-s") (λ (m e) m)))
    (define km2 (keymap-unbind km (kbd "C-s")))
    (check-false (keymap-lookup km2 (kbd "C-s"))))

  ;; Sequence matching tests
  (test-case "keyseq-prefix? detects prefix"
    (define full (kbd "C-x C-s"))
    (define prefix (kbd "C-x"))
    (check-true (keyseq-prefix? prefix full)))

  (test-case "keyseq-prefix? rejects non-prefix"
    (define full (kbd "C-x C-s"))
    (define other (kbd "C-c"))
    (check-false (keyseq-prefix? other full)))

  ;; Key sequence state tests
  (test-case "keyseq-state tracks pending"
    (define st (make-keyseq-state))
    (check-false (keyseq-state-pending? st))
    (define chord (make-keychord #:rune #\x #:modifiers '(ctrl)))
    (define st2 (keyseq-state-feed st chord))
    (check-true (keyseq-state-pending? st2)))

  (test-case "keyseq-state reset clears pending"
    (define st (make-keyseq-state))
    (define chord (make-keychord #:rune #\x))
    (define st2 (keyseq-state-feed st chord))
    (define st3 (keyseq-state-reset st2))
    (check-false (keyseq-state-pending? st3)))

  ;; Dispatch tests
  (test-case "dispatch-key executes single-key binding"
    (define handler-called? (box #f))
    (define km (keymap-bind (make-keymap)
                            (kbd "a")
                            (λ (m e)
                              (set-box! handler-called? #t)
                              (list (add1 m) '()))))
    (define st (make-keyseq-state))
    (define evt (make-key-event* #:rune #\a))
    (define result (dispatch-key km st evt 0))
    (check-true (unbox handler-called?))
    (check-true (dispatch-result-match? result))
    (check-equal? (dispatch-result-model result) 1))

  (test-case "dispatch-key handles multi-key sequence"
    (define km (keymap-bind (make-keymap)
                            (kbd "g g")
                            (λ (m e) (list 'matched '()))))
    (define st (make-keyseq-state))
    (define evt1 (make-key-event* #:rune #\g))
    (define evt2 (make-key-event* #:rune #\g))

    (define r1 (dispatch-key km st evt1 #f))
    (check-false (dispatch-result-match? r1))
    (check-true (keyseq-state-pending? (dispatch-result-state r1)))

    (define r2 (dispatch-key km (dispatch-result-state r1) evt2 #f))
    (check-true (dispatch-result-match? r2))
    (check-equal? (dispatch-result-model r2) 'matched))

  (test-case "dispatch-key resets on non-matching partial"
    (define km (keymap-bind (make-keymap)
                            (kbd "g g")
                            (λ (m e) (values 'matched '()))))
    (define st (make-keyseq-state))
    (define evt1 (make-key-event* #:rune #\g))
    (define evt2 (make-key-event* #:rune #\x))

    (define r1 (dispatch-key km st evt1 #f))
    (define r2 (dispatch-key km (dispatch-result-state r1) evt2 #f))
    (check-false (dispatch-result-match? r2))
    (check-false (keyseq-state-pending? (dispatch-result-state r2))))

  ;; Built-in keymaps tests
  (test-case "default-keymap has arrow bindings"
    (check-not-false (keymap-lookup default-keymap (kbd "up")))
    (check-not-false (keymap-lookup default-keymap (kbd "down")))
    (check-not-false (keymap-lookup default-keymap (kbd "left")))
    (check-not-false (keymap-lookup default-keymap (kbd "right"))))

  (test-case "emacs-keymap has C-x C-s binding"
    (check-not-false (keymap-lookup emacs-keymap (kbd "C-x C-s"))))

  (test-case "emacs-keymap has basic movement"
    (check-not-false (keymap-lookup emacs-keymap (kbd "C-a")))
    (check-not-false (keymap-lookup emacs-keymap (kbd "C-e")))
    (check-not-false (keymap-lookup emacs-keymap (kbd "C-f")))
    (check-not-false (keymap-lookup emacs-keymap (kbd "C-b"))))

  ;; When predicate tests
  (test-case "binding respects when predicate"
    (define km (keymap-bind (make-keymap)
                            (kbd "a")
                            (λ (m e) m)
                            #:when (λ (ctx) (eq? ctx 'active))))
    (check-not-false (keymap-lookup km (kbd "a") 'active))
    (check-false (keymap-lookup km (kbd "a") 'inactive)))

  (test-case "define-keys macro works"
    (define km (define-keys (make-keymap)
                 ["a" (λ (m e) 'a) #:doc "letter a"]
                 ["b" (λ (m e) 'b) #:doc "letter b"]))
    (check-not-false (keymap-lookup km (kbd "a")))
    (check-not-false (keymap-lookup km (kbd "b")))
    (check-equal? (binding-doc (keymap-lookup km (kbd "a"))) "letter a")))
