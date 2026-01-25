#lang racket/base

(require racket/set
         racket/contract
         racket/match)

(provide (struct-out key-event)
         (struct-out mouse-event)
         (struct-out paste-event)
         (struct-out resize-event)
         (struct-out tick-event)
         (struct-out focus-event)
         (struct-out unknown-event)
         event?
         key-symbol?
         modifier?
         mouse-button?
         mouse-action?
         ctrl?
         alt?
         shift?
         meta?
         make-modifiers
         empty-modifiers
         key-symbols)

(define key-symbols
  '(up down left right
    enter esc tab backspace delete home end
    page-up page-down insert space
    f1 f2 f3 f4 f5 f6 f7 f8 f9 f10 f11 f12))

(define (key-symbol? v)
  (and (symbol? v)
       (or (memq v key-symbols)
           (eq? v 'unknown))))

(define (modifier? v)
  (memq v '(ctrl alt shift meta)))

(define (mouse-button? v)
  (memq v '(left middle right scroll-up scroll-down none)))

(define (mouse-action? v)
  (memq v '(press release motion)))

(struct key-event (key rune modifiers raw)
  #:transparent
  #:guard (λ (key rune mods raw name)
            (values (if (or (key-symbol? key) (not key)) key 'unknown)
                    (if (or (char? rune) (not rune)) rune #f)
                    (if (set? mods) mods (set))
                    (if (bytes? raw) raw #""))))

(struct mouse-event (x y button action modifiers)
  #:transparent
  #:guard (λ (x y btn act mods name)
            (values (if (exact-nonnegative-integer? x) x 0)
                    (if (exact-nonnegative-integer? y) y 0)
                    (if (mouse-button? btn) btn 'none)
                    (if (mouse-action? act) act 'press)
                    (if (set? mods) mods (set)))))

(struct paste-event (text)
  #:transparent
  #:guard (λ (text name)
            (values (if (string? text) text ""))))

(struct resize-event (width height)
  #:transparent
  #:guard (λ (w h name)
            (values (if (exact-positive-integer? w) w 80)
                    (if (exact-positive-integer? h) h 24))))

(struct tick-event (timestamp-ms)
  #:transparent
  #:guard (λ (ts name)
            (values (if (exact-nonnegative-integer? ts) ts 0))))

(struct focus-event (focused?)
  #:transparent
  #:guard (λ (f? name)
            (values (and f? #t))))

(struct unknown-event (raw)
  #:transparent
  #:guard (λ (raw name)
            (values (if (bytes? raw) raw #""))))

(define (event? v)
  (or (key-event? v)
      (mouse-event? v)
      (paste-event? v)
      (resize-event? v)
      (tick-event? v)
      (focus-event? v)
      (unknown-event? v)))

(define empty-modifiers (set))

(define (make-modifiers . mods)
  (for/set ([m (in-list mods)]
            #:when (modifier? m))
    m))

(define (ctrl? evt)
  (match evt
    [(key-event _ _ mods _) (set-member? mods 'ctrl)]
    [(mouse-event _ _ _ _ mods) (set-member? mods 'ctrl)]
    [_ #f]))

(define (alt? evt)
  (match evt
    [(key-event _ _ mods _) (set-member? mods 'alt)]
    [(mouse-event _ _ _ _ mods) (set-member? mods 'alt)]
    [_ #f]))

(define (shift? evt)
  (match evt
    [(key-event _ _ mods _) (set-member? mods 'shift)]
    [(mouse-event _ _ _ _ mods) (set-member? mods 'shift)]
    [_ #f]))

(define (meta? evt)
  (match evt
    [(key-event _ _ mods _) (set-member? mods 'meta)]
    [(mouse-event _ _ _ _ mods) (set-member? mods 'meta)]
    [_ #f]))

(module+ test
  (require rackunit)
  
  (test-case "key-event construction"
    (define evt (key-event 'enter #f (set 'ctrl) #"\r"))
    (check-eq? (key-event-key evt) 'enter)
    (check-false (key-event-rune evt))
    (check-true (ctrl? evt))
    (check-false (alt? evt)))
  
  (test-case "key-event with rune"
    (define evt (key-event #f #\a (set) #"a"))
    (check-false (key-event-key evt))
    (check-equal? (key-event-rune evt) #\a))
  
  (test-case "mouse-event construction"
    (define evt (mouse-event 10 20 'left 'press (set 'shift)))
    (check-equal? (mouse-event-x evt) 10)
    (check-equal? (mouse-event-y evt) 20)
    (check-eq? (mouse-event-button evt) 'left)
    (check-true (shift? evt)))
  
  (test-case "paste-event"
    (define evt (paste-event "hello world"))
    (check-equal? (paste-event-text evt) "hello world"))
  
  (test-case "resize-event"
    (define evt (resize-event 120 40))
    (check-equal? (resize-event-width evt) 120)
    (check-equal? (resize-event-height evt) 40))
  
  (test-case "tick-event"
    (define evt (tick-event 12345))
    (check-equal? (tick-event-timestamp-ms evt) 12345))
  
  (test-case "focus-event"
    (check-true (focus-event-focused? (focus-event #t)))
    (check-false (focus-event-focused? (focus-event #f))))
  
  (test-case "unknown-event"
    (define evt (unknown-event #"\e[?999"))
    (check-equal? (unknown-event-raw evt) #"\e[?999"))
  
  (test-case "modifier helpers"
    (define mods (make-modifiers 'ctrl 'alt 'invalid))
    (check-true (set-member? mods 'ctrl))
    (check-true (set-member? mods 'alt))
    (check-false (set-member? mods 'invalid)))
  
  (test-case "event? predicate"
    (check-true (event? (key-event 'enter #f (set) #"")))
    (check-true (event? (mouse-event 0 0 'left 'press (set))))
    (check-true (event? (paste-event "")))
    (check-true (event? (resize-event 80 24)))
    (check-true (event? (tick-event 0)))
    (check-true (event? (focus-event #t)))
    (check-true (event? (unknown-event #"")))
    (check-false (event? "not an event"))))
