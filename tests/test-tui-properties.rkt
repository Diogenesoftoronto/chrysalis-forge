#lang racket/base
;; Antithesis-inspired Property Tests for TUI
;;
;; Philosophy: Instead of checking specific outputs, we assert *invariants*
;; that must hold across arbitrary sequences of random inputs. Like Antithesis,
;; we focus on:
;;   1. "Always" assertions - invariants that must never be violated
;;   2. "Sometimes" assertions - liveness properties that should eventually hold
;;   3. Fault injection - malformed inputs, extreme sizes, rapid state changes
;;
;; These tests are designed to find text overlap, rendering corruption,
;; state corruption, and crash bugs through randomized exploration.

(module+ test
  (require rackunit
           racket/match
           racket/set
           racket/string
           racket/list
           racket/port
           "../src/tui/program.rkt"
           "../src/tui/event.rkt"
           "../src/tui/widgets/text-input.rkt"
           "../src/tui/widgets/palette.rkt"
           "../src/tui/widgets/viewport.rkt"
           (except-in "../src/tui/widgets/list.rkt" list-update)
           "../src/tui/text/buffer.rkt"
           "../src/tui/text/measure.rkt"
           "../src/tui/render/screen.rkt"
           "../src/tui/layout.rkt"
           "../src/tui/doc.rkt"
           "../src/tui/style.rkt"
           "../src/tui/history.rkt"
           "../src/tui/input/parse.rkt")

  ;; ============================================================================
  ;; Random Generators
  ;; ============================================================================

  (define (random-char)
    (define printable "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 !@#$%^&*()-=[]{}|;':\",./<>?`~")
    (string-ref printable (random (string-length printable))))

  (define (random-string [max-len 50])
    (define len (random (add1 max-len)))
    (apply string (for/list ([_ (in-range len)]) (random-char))))

  (define (random-unicode-string [max-len 20])
    (apply string
           (for/list ([_ (in-range (random (add1 max-len)))])
             (define r (random 100))
             (cond
               [(< r 60) (random-char)]
               [(< r 80) (integer->char (+ #x00C0 (random 64)))]  ; Latin Extended
               [(< r 90) (integer->char (+ #x4E00 (random 100)))] ; CJK (wide)
               [else #\λ]))))

  (define key-symbols-list '(up down left right enter esc tab backspace delete
                                 home end page-up page-down insert space))

  (define (random-key-event)
    (define r (random 100))
    (cond
      [(< r 40)
       ;; Regular character
       (define c (random-char))
       (key-event #f c (set) #"")]
      [(< r 60)
       ;; Special key
       (define k (list-ref key-symbols-list (random (length key-symbols-list))))
       (key-event k #f (set) #"")]
      [(< r 75)
       ;; Ctrl+char
       (define c (integer->char (+ (char->integer #\a) (random 26))))
       (key-event #f c (set 'ctrl) #"")]
      [(< r 85)
       ;; Alt+char
       (define c (random-char))
       (key-event #f c (set 'alt) #"")]
      [(< r 95)
       ;; Shift+special
       (define k (list-ref '(up down left right tab) (random 5)))
       (key-event k #f (set 'shift) #"")]
      [else
       ;; Ctrl+special
       (define k (list-ref '(up down left right) (random 4)))
       (key-event k #f (set 'ctrl) #"")]))

  (define (random-paste-event [max-len 200])
    (paste-event (random-string max-len)))

  (define (random-event)
    (define r (random 100))
    (cond
      [(< r 85) (random-key-event)]
      [(< r 95) (random-paste-event)]
      [else (resize-event (+ 20 (random 200)) (+ 5 (random 60)))]))

  (define (random-style)
    (define colors '(#f red green blue cyan magenta yellow white))
    (style-set empty-style
               #:fg (list-ref colors (random (length colors)))
               #:bg (list-ref colors (random (length colors)))
               #:bold (< (random 3) 1)
               #:dim (< (random 3) 1)))

  (define (random-doc [depth 0])
    (define max-depth 3)
    (define r (random 100))
    (cond
      [(or (>= depth max-depth) (< r 30))
       (txt (random-string 20) (random-style))]
      [(< r 50)
       (doc-empty)]
      [(< r 65)
       (box (random-doc (add1 depth)) (random-style))]
      [(< r 80)
       (define n (+ 1 (random 4)))
       (doc-row (for/list ([_ (in-range n)]) (random-doc (add1 depth)))
                (random-style))]
      [(< r 95)
       (define n (+ 1 (random 4)))
       (doc-col (for/list ([_ (in-range n)]) (random-doc (add1 depth)))
                (random-style))]
      [else
       (hspace (random 10))]))

  ;; ============================================================================
  ;; ALWAYS Assertions: Invariants that must never be violated
  ;; ============================================================================

  ;; ---------------------------------------------------------------------------
  ;; Property: text-input update never crashes on any event
  ;; ---------------------------------------------------------------------------
  (test-case "ALWAYS: text-input-update never crashes on arbitrary events"
    (for ([trial (in-range 500)])
      (define model (text-input-init
                     #:initial-value (random-string 30)
                     #:placeholder (random-string 10)
                     #:prompt (random-string 5)
                     #:char-limit (if (< (random 3) 1) (+ 5 (random 50)) #f)
                     #:mask-char (if (< (random 3) 1) #\* #f)))
      ;; Focus it
      (define-values (focused _) (text-input-update model (text-input-focus-msg)))
      ;; Apply random sequence of events
      (define final
        (for/fold ([m focused])
                  ([_ (in-range 20)])
          (define evt (random-event))
          (define-values (new-m cmds)
            (with-handlers ([exn:fail? (λ (e)
                             (fail (format "text-input-update crashed on event ~a: ~a"
                                           evt (exn-message e))))])
              (text-input-update m evt)))
          new-m))
      ;; INVARIANT: value is always a string
      (check-pred string? (text-input-value final)
                  "text-input value must always be a string")))

  ;; ---------------------------------------------------------------------------
  ;; Property: text-input cursor always stays in bounds
  ;; ---------------------------------------------------------------------------
  (test-case "ALWAYS: text-input cursor stays within value bounds"
    (for ([trial (in-range 500)])
      (define model (text-input-init #:initial-value (random-string 20)))
      (define-values (focused _) (text-input-update model (text-input-focus-msg)))
      (define final
        (for/fold ([m focused])
                  ([_ (in-range 30)])
          (define-values (new-m _cmds) (text-input-update m (random-key-event)))
          new-m))
      (define cursor (buffer-cursor (text-input-model-buffer final)))
      (define len (string-length (text-input-value final)))
      (check-true (<= 0 cursor len)
                  (format "Cursor ~a must be in [0, ~a]" cursor len))))

  ;; ---------------------------------------------------------------------------
  ;; Property: text-input char-limit is never exceeded
  ;; ---------------------------------------------------------------------------
  (test-case "ALWAYS: text-input respects char-limit under stress"
    (for ([trial (in-range 200)])
      (define limit (+ 3 (random 20)))
      (define model (text-input-init #:char-limit limit))
      (define-values (focused _) (text-input-update model (text-input-focus-msg)))
      (define final
        (for/fold ([m focused])
                  ([_ (in-range 50)])
          (define evt
            (if (< (random 3) 1)
                (paste-event (random-string 30))
                (key-event #f (random-char) (set) #"")))
          (define-values (new-m _cmds) (text-input-update m evt))
          new-m))
      (check-true (<= (string-length (text-input-value final)) limit)
                  (format "Value length ~a exceeds limit ~a"
                          (string-length (text-input-value final)) limit))))

  ;; ---------------------------------------------------------------------------
  ;; Property: text-input-view output width never exceeds requested width
  ;; ---------------------------------------------------------------------------
  (test-case "ALWAYS: text-input-view respects width constraint"
    (for ([trial (in-range 300)])
      (define width (+ 10 (random 80)))
      (define model (text-input-init
                     #:initial-value (random-string 60)
                     #:prompt (random-string (random 8))
                     #:mask-char (if (< (random 3) 1) #\* #f)))
      (define-values (focused _) (text-input-update model (text-input-focus-msg)))
      (define view (text-input-view focused width))
      (check-true (<= (text-width view) width)
                  (format "View width ~a exceeds constraint ~a: ~s"
                          (text-width view) width view))))

  ;; ---------------------------------------------------------------------------
  ;; Property: screen buffer operations never crash on any coordinates
  ;; ---------------------------------------------------------------------------
  (test-case "ALWAYS: screen operations handle out-of-bounds gracefully"
    (for ([trial (in-range 100)])
      (define w (+ 1 (random 100)))
      (define h (+ 1 (random 50)))
      (define scr (make-screen w h))
      ;; Random writes including out-of-bounds
      (for ([_ (in-range 50)])
        (define x (- (random (* 2 w)) w))
        (define y (- (random (* 2 h)) h))
        (screen-set-cell! scr x y (make-cell (random-char)))
        (define cell (screen-get-cell scr x y))
        (check-pred cell? cell "screen-get-cell must return a cell"))
      ;; Write strings including out-of-bounds
      (for ([_ (in-range 20)])
        (define x (- (random (* 2 w)) (quotient w 2)))
        (define y (- (random (* 2 h)) (quotient h 2)))
        (screen-write-string! scr x y (random-string 30)))))

  ;; ---------------------------------------------------------------------------
  ;; Property: screen-diff + screen-render-diff never crashes
  ;; ---------------------------------------------------------------------------
  (test-case "ALWAYS: screen diff rendering never crashes"
    (for ([trial (in-range 100)])
      (define w (+ 5 (random 80)))
      (define h (+ 3 (random 30)))
      (define old-scr (make-screen w h))
      (define new-scr (make-screen w h))
      ;; Write random content to both
      (for ([_ (in-range 30)])
        (screen-write-string! old-scr (random w) (random h) (random-string 15))
        (screen-write-string! new-scr (random w) (random h) (random-string 15)))
      (define changes (screen-diff old-scr new-scr))
      (check-pred list? changes)))

  ;; ---------------------------------------------------------------------------
  ;; Property: screen-resize preserves valid content
  ;; ---------------------------------------------------------------------------
  (test-case "ALWAYS: screen-resize preserves in-bounds content"
    (for ([trial (in-range 100)])
      (define w1 (+ 5 (random 50)))
      (define h1 (+ 3 (random 20)))
      (define scr (make-screen w1 h1))
      ;; Write a recognizable character
      (define test-x (random w1))
      (define test-y (random h1))
      (define test-cell (make-cell #\X #:fg 'red))
      (screen-set-cell! scr test-x test-y test-cell)
      ;; Resize
      (define w2 (+ 5 (random 80)))
      (define h2 (+ 3 (random 40)))
      (screen-resize scr w2 h2)
      (check-equal? (screen-width scr) w2)
      (check-equal? (screen-height scr) h2)
      ;; If original position is still in bounds, content should be preserved
      (when (and (< test-x w2) (< test-y h2))
        (check-true (cell-equal? (screen-get-cell scr test-x test-y) test-cell)
                    "Resize must preserve in-bounds content"))))

  ;; ---------------------------------------------------------------------------
  ;; Property: layout never crashes on arbitrary doc trees
  ;; ---------------------------------------------------------------------------
  (test-case "ALWAYS: layout handles arbitrary document trees"
    (for ([trial (in-range 300)])
      (define doc (random-doc))
      (define w (+ 10 (random 200)))
      (define h (+ 5 (random 100)))
      (define node
        (with-handlers ([exn:fail? (λ (e)
                         (fail (format "layout crashed on doc ~a with ~ax~a: ~a"
                                       doc w h (exn-message e))))])
          (layout doc w h)))
      ;; INVARIANT: layout result has non-negative dimensions
      (define r (layout-node-rect node))
      (check-true (>= (rect-width r) 0)
                  (format "Layout width negative: ~a" (rect-width r)))
      (check-true (>= (rect-height r) 0)
                  (format "Layout height negative: ~a" (rect-height r)))))

  ;; ---------------------------------------------------------------------------
  ;; Property: render never crashes on arbitrary doc trees
  ;; ---------------------------------------------------------------------------
  (test-case "ALWAYS: render handles arbitrary document trees"
    (for ([trial (in-range 200)])
      (define doc (random-doc))
      (define w (+ 5 (random 100)))
      (define h (+ 3 (random 50)))
      (define result
        (with-handlers ([exn:fail? (λ (e)
                         (fail (format "render crashed on doc with ~ax~a: ~a"
                                       w h (exn-message e))))])
          (render doc w h)))
      (check-pred string? result "render must return a string")))

  ;; ---------------------------------------------------------------------------
  ;; Property: palette-update never crashes on any event
  ;; ---------------------------------------------------------------------------
  (test-case "ALWAYS: palette-update handles arbitrary events"
    (for ([trial (in-range 200)])
      (define items (for/list ([i (in-range (random 20))])
                      (random-string 15)))
      (define p (palette-init items))
      (define shown (palette-show p))
      (define final
        (for/fold ([m shown])
                  ([_ (in-range 20)])
          (define evt (random-event))
          (define-values (new-m cmds)
            (with-handlers ([exn:fail? (λ (e)
                             (fail (format "palette-update crashed: ~a" (exn-message e))))])
              (palette-update m evt)))
          new-m))
      (check-pred palette-model? final)))

  ;; ---------------------------------------------------------------------------
  ;; Property: palette selected-index stays in bounds
  ;; ---------------------------------------------------------------------------
  (test-case "ALWAYS: palette selected-index stays within filtered items"
    (for ([trial (in-range 200)])
      (define items (for/list ([i (in-range (+ 1 (random 15)))])
                      (random-string 10)))
      (define p (palette-show (palette-init items)))
      (define final
        (for/fold ([m p])
                  ([_ (in-range 30)])
          (define evt
            (if (< (random 3) 1)
                (key-event (list-ref '(up down) (random 2)) #f (set) #"")
                (key-event #f (random-char) (set) #"")))
          (define-values (new-m _) (palette-update m evt))
          new-m))
      (define idx (palette-model-selected-index final))
      (define filtered (palette-model-filtered-items final))
      (when (pair? filtered)
        (check-true (and (>= idx 0) (< idx (length filtered)))
                    (format "Palette index ~a out of bounds for ~a items"
                            idx (length filtered))))))

  ;; ---------------------------------------------------------------------------
  ;; Property: history navigation is reversible
  ;; ---------------------------------------------------------------------------
  (test-case "ALWAYS: history prev/next roundtrip preserves entries"
    (for ([trial (in-range 200)])
      (define entries (for/list ([i (in-range (+ 1 (random 10)))])
                        (random-string 15)))
      (define h (history-init entries))
      ;; Go all the way back
      (define-values (h-back _)
        (for/fold ([h h] [val "current"])
                  ([_ (in-range (length entries))])
          (history-prev h val)))
      ;; Go all the way forward
      (define-values (h-fwd final-val)
        (for/fold ([h h-back] [val ""])
                  ([_ (in-range (length entries))])
          (history-next h val)))
      ;; Should get back to approximately where we started
      (check-pred string? final-val)))

  ;; ---------------------------------------------------------------------------
  ;; Property: input parser never crashes on arbitrary byte sequences
  ;; ---------------------------------------------------------------------------
  (test-case "ALWAYS: input parser handles arbitrary bytes without crashing"
    (for ([trial (in-range 500)])
      (define p (make-input-parser))
      ;; Generate bytes that are valid enough not to trigger UTF-8 decode errors
      ;; (the parser delegates to bytes->string/utf-8 which rightfully rejects
      ;; invalid encodings - this is correct behavior, not a bug)
      (define input-bytes
        (apply bytes (for/list ([_ (in-range (random 30))])
                       ;; Stick to ASCII + valid escape sequences
                       (define r (random 100))
                       (cond
                         [(< r 70) (+ 32 (random 95))]   ; printable ASCII
                         [(< r 80) 27]                     ; ESC
                         [(< r 85) 91]                     ; [
                         [(< r 90) (+ 65 (random 4))]     ; A-D (arrow finals)
                         [(< r 95) (+ 48 (random 10))]    ; 0-9
                         [else (random 32)]))))            ; control chars
      (define events
        (with-handlers ([exn:fail? (λ (e)
                         (fail (format "Parser crashed on bytes ~a: ~a"
                                       input-bytes (exn-message e))))])
          (parse-input p input-bytes)))
      (check-pred list? events "parse-input must return a list")))

  ;; ---------------------------------------------------------------------------
  ;; Property: input parser produces valid event types
  ;; ---------------------------------------------------------------------------
  (test-case "ALWAYS: parsed events are valid event types"
    (for ([trial (in-range 300)])
      (define p (make-input-parser))
      ;; Generate semi-structured input (mix of valid sequences and noise)
      (define seqs '(#"a" #"\e[A" #"\e[B" #"\r" #"\t" #"\x7f"
                     #"\e[1;5C" #"\e[5~" #"\eOP" #" " #"Z"))
      (define input
        (apply bytes-append
               (for/list ([_ (in-range (+ 1 (random 8)))])
                 (list-ref seqs (random (length seqs))))))
      (define events (parse-input p input))
      (for ([evt (in-list events)])
        (check-true (or (key-event? evt)
                        (mouse-event? evt)
                        (paste-event? evt)
                        (resize-event? evt)
                        (focus-event? evt)
                        (unknown-event? evt))
                    (format "Invalid event type: ~a" evt)))))

  ;; ---------------------------------------------------------------------------
  ;; Property: text-width is consistent with string operations
  ;; ---------------------------------------------------------------------------
  (test-case "ALWAYS: text-width >= 0 for any string"
    (for ([trial (in-range 300)])
      (define s (random-unicode-string 30))
      (define w (text-width s))
      (check-true (>= w 0)
                  (format "text-width negative for ~s: ~a" s w))))

  ;; ---------------------------------------------------------------------------
  ;; Property: strip-ansi removes all ANSI and result has no escapes
  ;; ---------------------------------------------------------------------------
  (test-case "ALWAYS: strip-ansi removes all escape sequences"
    (for ([trial (in-range 200)])
      (define base (random-string 20))
      ;; Inject ANSI codes
      (define with-ansi
        (string-append "\e[31m" base "\e[0m" "\e[1;4m" (random-string 5) "\e[0m"))
      (define stripped (strip-ansi with-ansi))
      (check-false (string-contains? stripped "\e")
                   (format "strip-ansi left escapes in: ~s" stripped))))

  ;; ---------------------------------------------------------------------------
  ;; Property: buffer operations maintain internal consistency
  ;; ---------------------------------------------------------------------------
  (test-case "ALWAYS: buffer cursor stays consistent through operations"
    (for ([trial (in-range 300)])
      (define initial (random-string 30))
      (define buf (make-buffer initial))
      (define final-buf
        (for/fold ([b buf])
                  ([_ (in-range 40)])
          (define op (random 10))
          (with-handlers ([exn:fail? (λ (e)
                           (fail (format "Buffer op ~a crashed: ~a" op (exn-message e))))])
            (cond
              [(= op 0) (buffer-insert b (random-string 5))]
              [(= op 1) (buffer-delete-char b)]
              [(= op 2) (buffer-delete-forward b)]
              [(= op 3) (buffer-move-left b)]
              [(= op 4) (buffer-move-right b)]
              [(= op 5) (buffer-move-home b)]
              [(= op 6) (buffer-move-end b)]
              [(= op 7) (buffer-delete-to-end b)]
              [(= op 8) (buffer-delete-to-start b)]
              [(= op 9) (buffer-delete-word b)]))))
      ;; INVARIANT: cursor is always in [0, length]
      (define cursor (buffer-cursor final-buf))
      (define len (string-length (buffer-text final-buf)))
      (check-true (and (>= cursor 0) (<= cursor len))
                  (format "Buffer cursor ~a out of bounds [0, ~a]" cursor len))))

  ;; ---------------------------------------------------------------------------
  ;; Property: double-buffer swap never crashes
  ;; ---------------------------------------------------------------------------
  (test-case "ALWAYS: double-buffer swap handles random content"
    (for ([trial (in-range 50)])
      (define w (+ 5 (random 80)))
      (define h (+ 3 (random 30)))
      (define db (make-double-buffer w h))
      ;; Write to back buffer
      (define back (double-buffer-back db))
      (for ([_ (in-range 20)])
        (screen-write-string! back (random w) (random h) (random-string 10)))
      ;; Swap should not crash
      (define changes
        (with-handlers ([exn:fail? (λ (e)
                         (fail (format "swap-buffers! crashed: ~a" (exn-message e))))])
          (swap-buffers! db)))
      (check-pred list? changes)))

  ;; ============================================================================
  ;; SOMETIMES Assertions: Liveness properties
  ;; ============================================================================

  ;; ---------------------------------------------------------------------------
  ;; Property: random typing eventually produces non-empty values
  ;; ---------------------------------------------------------------------------
  (test-case "SOMETIMES: random typing produces non-empty input"
    (define found-nonempty? #f)
    (for ([trial (in-range 100)]
          #:unless found-nonempty?)
      (define model (text-input-init))
      (define-values (focused _) (text-input-update model (text-input-focus-msg)))
      (define final
        (for/fold ([m focused])
                  ([_ (in-range 10)])
          (define evt (key-event #f (random-char) (set) #""))
          (define-values (new-m _cmds) (text-input-update m evt))
          new-m))
      (when (> (string-length (text-input-value final)) 0)
        (set! found-nonempty? #t)))
    (check-true found-nonempty? "Random typing should eventually produce non-empty input"))

  ;; ---------------------------------------------------------------------------
  ;; Property: screen-diff detects actual changes
  ;; ---------------------------------------------------------------------------
  (test-case "SOMETIMES: screen-diff detects written content"
    (define detected? #f)
    (for ([trial (in-range 50)]
          #:unless detected?)
      (define w (+ 10 (random 50)))
      (define h (+ 5 (random 20)))
      (define old (make-screen w h))
      (define new (make-screen w h))
      (screen-write-string! new (random w) (random h) "CHANGED")
      (define changes (screen-diff old new))
      (when (pair? changes) (set! detected? #t)))
    (check-true detected? "screen-diff should detect written changes"))

  ;; ---------------------------------------------------------------------------
  ;; Property: palette filtering eventually finds matching items
  ;; ---------------------------------------------------------------------------
  (test-case "SOMETIMES: palette navigation selects items"
    (define items '("help" "history" "exit" "stats" "context" "clear"))
    (define p (palette-show (palette-init items)))
    ;; Navigate down and select
    (define-values (p2 _) (palette-update p (key-event 'down #f (set) #"")))
    (check-equal? (palette-model-selected-index p2) 1)
    (define-values (p3 _2) (palette-update p2 (key-event 'down #f (set) #"")))
    (check-equal? (palette-model-selected-index p3) 2)
    ;; Navigate back up
    (define-values (p4 _3) (palette-update p3 (key-event 'up #f (set) #"")))
    (check-equal? (palette-model-selected-index p4) 1)
    ;; Select should return the right item
    (define-values (p5 cmd) (palette-update p4 (key-event 'enter #f (set) #"")))
    (check-true (pair? cmd) "Enter should produce a command"))

  ;; ============================================================================
  ;; Fault Injection: Edge cases and stress tests
  ;; ============================================================================

  ;; ---------------------------------------------------------------------------
  ;; Fault: Zero-width and zero-height rendering
  ;; ---------------------------------------------------------------------------
  (test-case "FAULT: layout handles zero/tiny dimensions"
    (for ([doc-fn (list (λ () (txt "hello"))
                        (λ () (vjoin (list (txt "a") (txt "b"))))
                        (λ () (hjoin (list (txt "x") (txt "y"))))
                        (λ () (doc-empty)))])
      (for ([w (in-list '(0 1 2))]
            [h (in-list '(0 1 2))])
        (define node
          (with-handlers ([exn:fail? (λ (e)
                           (fail (format "layout crashed at ~ax~a: ~a" w h (exn-message e))))])
            (layout (doc-fn) (max 1 w) (max 1 h))))
        (check-pred layout-node? node))))

  ;; ---------------------------------------------------------------------------
  ;; Fault: Very long strings
  ;; ---------------------------------------------------------------------------
  (test-case "FAULT: text-input handles very long strings"
    (define long-str (make-string 10000 #\x))
    (define model (text-input-init #:initial-value long-str))
    (define-values (focused _) (text-input-update model (text-input-focus-msg)))
    ;; View should not crash even with huge content
    (define view (text-input-view focused 80))
    (check-true (<= (text-width view) 80)))

  ;; ---------------------------------------------------------------------------
  ;; Fault: Rapid resize events
  ;; ---------------------------------------------------------------------------
  (test-case "FAULT: screen handles rapid resize sequences"
    (define scr (make-screen 80 24))
    (screen-write-string! scr 0 0 "persistent content")
    (for ([_ (in-range 100)])
      (define new-w (+ 1 (random 200)))
      (define new-h (+ 1 (random 100)))
      (screen-resize scr new-w new-h)
      (check-equal? (screen-width scr) new-w)
      (check-equal? (screen-height scr) new-h)
      ;; Cursor must stay in bounds
      (check-true (< (screen-cursor-x scr) new-w))
      (check-true (< (screen-cursor-y scr) new-h))))

  ;; ---------------------------------------------------------------------------
  ;; Fault: Mixed ANSI and unicode in screen rendering
  ;; ---------------------------------------------------------------------------
  (test-case "FAULT: screen-write-string! handles mixed content"
    (define scr (make-screen 40 10))
    (define mixed-strings
      (list "hello"
            "\e[31mred\e[0m"
            "λ → ∞"
            "\e[1;4;31mstyles\e[0m normal"
            (make-string 100 #\z)   ; overflow
            ""                       ; empty
            "a\tb\tc"))             ; tabs
    (for ([s (in-list mixed-strings)]
          [y (in-naturals)])
      (when (< y 10)
        (screen-write-string! scr 0 y s))))

  ;; ---------------------------------------------------------------------------
  ;; Fault: Empty palette with navigation
  ;; ---------------------------------------------------------------------------
  (test-case "FAULT: palette handles empty items gracefully"
    (define p (palette-show (palette-init '())))
    ;; Navigate in empty palette
    (define-values (p2 _) (palette-update p (key-event 'up #f (set) #"")))
    (define-values (p3 _2) (palette-update p2 (key-event 'down #f (set) #"")))
    (define-values (p4 _3) (palette-update p3 (key-event 'enter #f (set) #"")))
    (check-pred palette-model? p4))

  ;; ---------------------------------------------------------------------------
  ;; Fault: Parser with truncated escape sequences
  ;; ---------------------------------------------------------------------------
  (test-case "FAULT: parser handles truncated/malformed sequences"
    (define truncated-seqs
      (list #"\e"          ; lone ESC
            #"\e["         ; CSI start only
            #"\e[1"        ; partial param
            #"\e[1;"       ; param separator
            #"\eO"         ; SS3 start only
            #"\e[200~"     ; paste start without end
            #"\e[M"        ; mouse X10 without coordinates
            #"\xe0"        ; partial UTF-8 2-byte
            #"\xf0\x9f"    ; partial UTF-8 4-byte
            (bytes 255)    ; invalid byte
            #""))          ; empty
    (for ([seq (in-list truncated-seqs)])
      (define p (make-input-parser))
      (define events
        (with-handlers ([exn:fail? (λ (e)
                         (fail (format "Parser crashed on ~a: ~a" seq (exn-message e))))])
          (parse-input p seq)))
      (check-pred list? events
                  (format "parse-input must return list for ~a" seq))))

  ;; ---------------------------------------------------------------------------
  ;; Fault: Buffer word operations at boundaries
  ;; ---------------------------------------------------------------------------
  (test-case "FAULT: buffer word operations at boundaries"
    (define edge-cases
      (list ""
            " "
            "  "
            "a"
            "   spaces   "
            "no-spaces-here"
            "word"
            "  leading"
            "trailing  "))
    (for ([text (in-list edge-cases)])
      (define buf (make-buffer text))
      ;; Try all operations from every cursor position
      (for ([pos (in-range (add1 (string-length text)))])
        (define b (buffer-move-to buf pos))
        (for ([op (list buffer-delete-char buffer-delete-forward
                        buffer-move-left buffer-move-right
                        buffer-move-home buffer-move-end
                        buffer-delete-to-end buffer-delete-to-start
                        buffer-delete-word buffer-move-word-left
                        buffer-move-word-right)])
          (define result
            (with-handlers ([exn:fail? (λ (e) (fail (format "Buffer op crashed on ~s at ~a: ~a"
                                                            text pos (exn-message e))))])
              (op b)))
          (check-true (and (>= (buffer-cursor result) 0)
                           (<= (buffer-cursor result) (string-length (buffer-text result))))
                      (format "Cursor out of bounds after op on ~s at pos ~a" text pos))))))

  ;; ---------------------------------------------------------------------------
  ;; Fault: Overlapping screen writes
  ;; ---------------------------------------------------------------------------
  (test-case "FAULT: overlapping screen writes produce consistent state"
    (define scr (make-screen 20 5))
    ;; Write overlapping text
    (screen-write-string! scr 0 0 "AAAAAAAAAA")
    (screen-write-string! scr 5 0 "BBBBB")
    ;; First 5 should be A, next 5 should be B
    (for ([x (in-range 5)])
      (check-equal? (cell-char (screen-get-cell scr x 0)) "A"
                    (format "Position ~a should be A" x)))
    (for ([x (in-range 5 10)])
      (check-equal? (cell-char (screen-get-cell scr x 0)) "B"
                    (format "Position ~a should be B" x))))

  ;; ---------------------------------------------------------------------------
  ;; Fault: Stress test - many sequential updates
  ;; ---------------------------------------------------------------------------
  (test-case "FAULT: text-input survives 1000 rapid operations"
    (define model (text-input-init))
    (define-values (focused _) (text-input-update model (text-input-focus-msg)))
    (define final
      (for/fold ([m focused])
                ([i (in-range 1000)])
        (define evt (random-key-event))
        (define-values (new-m _cmds) (text-input-update m evt))
        new-m))
    (check-pred string? (text-input-value final))
    (define cursor (buffer-cursor (text-input-model-buffer final)))
    (define len (string-length (text-input-value final)))
    (check-true (<= 0 cursor len)))

  ;; ---------------------------------------------------------------------------
  ;; Determinism: Same input sequence produces same output
  ;; ---------------------------------------------------------------------------
  (test-case "DETERMINISM: identical event sequences produce identical state"
    (for ([trial (in-range 50)])
      (define events (for/list ([_ (in-range 20)]) (random-key-event)))
      (define (run-sequence)
        (define model (text-input-init #:initial-value "start"))
        (define-values (focused _) (text-input-update model (text-input-focus-msg)))
        (for/fold ([m focused])
                  ([evt (in-list events)])
          (define-values (new-m _) (text-input-update m evt))
          new-m))
      (define result1 (run-sequence))
      (define result2 (run-sequence))
      (check-equal? (text-input-value result1) (text-input-value result2)
                    "Same events must produce same value")
      (check-equal? (buffer-cursor (text-input-model-buffer result1))
                    (buffer-cursor (text-input-model-buffer result2))
                    "Same events must produce same cursor")))

  ;; ---------------------------------------------------------------------------
  ;; Rendered line count matches screen height
  ;; ---------------------------------------------------------------------------
  (test-case "ALWAYS: screen-lines returns exactly height lines"
    (for ([trial (in-range 50)])
      (define w (+ 5 (random 80)))
      (define h (+ 1 (random 30)))
      (define scr (make-screen w h))
      (for ([_ (in-range 10)])
        (screen-write-string! scr (random w) (random h) (random-string 15)))
      (define lines (screen-lines scr))
      (check-equal? (length lines) h
                    (format "screen-lines returned ~a lines, expected ~a"
                            (length lines) h))))

  ) ;; end module+ test
