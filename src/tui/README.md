# TUI Framework

A production-quality terminal UI framework for Racket, inspired by [Bubble Tea](https://github.com/charmbracelet/bubbletea) and [Lipgloss](https://github.com/charmbracelet/lipgloss).

## Features

- **Elm Architecture**: Predictable `init → update → view` pattern
- **Lipgloss-style Styling**: Colors, borders, padding, margins, alignment
- **Flexbox-like Layouts**: Rows, columns, flex grow/shrink
- **Rich Widgets**: Text input, textarea, viewport, selection list
- **Declarative Keybindings**: Key sequences, modifiers, mode-gated bindings
- **Efficient Rendering**: Diff-based screen updates

## Quick Start

```racket
#lang racket/base
(require "tui/tui.rkt")

;; Model
(struct app (counter) #:transparent)

;; Init
(define (init)
  (values (app 0) none))

;; Update
(define (update model msg)
  (match msg
    [(key-event 'esc _ _ _)
     (values model (quit))]
    [(key-event #f #\+ _ _)
     (values (app (add1 (app-counter model))) none)]
    [(key-event #f #\- _ _)
     (values (app (sub1 (app-counter model))) none)]
    [_ (values model none)]))

;; View
(define (view model size)
  (col
   (txt "Counter Demo" (style-set empty-style #:fg 'cyan #:bold #t))
   (vspace 1)
   (txt (format "Count: ~a" (app-counter model)))
   (vspace 1)
   (txt "Press +/- to change, ESC to quit")))

;; Run
(run-program #:init init #:update update #:view view)
```

## Architecture

### Elm-Style Loop

```
┌──────────────────────────────────────────┐
│                                          │
│    ┌──────┐    ┌────────┐    ┌──────┐   │
│    │ Init │───▶│ Model  │───▶│ View │   │
│    └──────┘    └────────┘    └──────┘   │
│                     ▲            │       │
│                     │            ▼       │
│                ┌────────┐   ┌────────┐  │
│                │ Update │◀──│ Events │  │
│                └────────┘   └────────┘  │
│                                          │
└──────────────────────────────────────────┘
```

### Module Structure

```
tui/
├── tui.rkt              # Main export module
├── terminal.rkt         # Raw terminal control (alt screen, cursor, mouse)
├── program.rkt          # Elm-style program runner
├── event.rkt            # Event types (key, mouse, paste, resize)
├── keymap.rkt           # Declarative key binding system
├── style.rkt            # Lipgloss-style styling
├── doc.rkt              # Document representation (composable UI)
├── layout.rkt           # Flexbox-like layout engine
├── text/
│   ├── measure.rkt      # Text width/height with ANSI handling
│   └── buffer.rkt       # Text editing buffer with cursor
├── widgets/
│   ├── text-input.rkt   # Single-line input
│   ├── textarea.rkt     # Multi-line editor
│   ├── viewport.rkt     # Scrollable container
│   └── list.rkt         # Selection list
├── render/
│   ├── screen.rkt       # Diff-based screen renderer
│   └── buffer.rkt       # 2D composition buffer
└── examples/
    └── demo.rkt         # Feature demo
```

## Core Concepts

### Styling

```racket
;; Create styles with style-set
(define my-style
  (style-set empty-style
             #:fg 'cyan
             #:bg 'black
             #:bold #t
             #:padding '(1 2 1 2)    ; top right bottom left
             #:border rounded-border
             #:border-fg 'magenta
             #:align 'center))

;; Available borders
rounded-border  ; ╭╮╰╯
square-border   ; ┌┐└┘
double-border   ; ╔╗╚╝
thick-border    ; ┏┓┗┛
hidden-border   ; spaces
```

### Documents (Composable UI)

```racket
;; Text with optional style
(txt "Hello" my-style)

;; Horizontal layout
(row (txt "Left") (spacer) (txt "Right"))

;; Vertical layout
(col (txt "Line 1") (txt "Line 2"))

;; Box with border/padding
(doc-block (txt "Content") box-style)

;; Fixed spacing
(hspace 5)  ; horizontal
(vspace 2)  ; vertical

;; Flex layout
(row
 (with-flex (txt "grows") #:grow 1)
 (txt "fixed"))

;; Overlay (for modals)
(stack background-doc modal-doc)
```

### Events

```racket
;; Key events
(key-event key rune modifiers raw)
; key: 'up 'down 'left 'right 'enter 'esc 'tab 'backspace ...
; rune: character for text input
; modifiers: set of 'ctrl 'alt 'shift 'meta

;; Check modifiers
(ctrl? evt)  ; Ctrl held?
(alt? evt)   ; Alt held?
(shift? evt) ; Shift held?

;; Other events
(resize-event width height)
(paste-event text)
(mouse-event x y button action modifiers)
```

### Keybindings

```racket
;; Parse key descriptions
(kbd "C-x C-s")  ; Ctrl+X followed by Ctrl+S
(kbd "M-g g")    ; Alt+G followed by G
(kbd "enter")    ; Enter key
(kbd "C-S-up")   ; Ctrl+Shift+Up

;; Build a keymap
(define my-keymap
  (define-keys (make-keymap)
    ["C-a" (λ (m e) (move-to-start m)) #:doc "Start of line"]
    ["C-e" (λ (m e) (move-to-end m)) #:doc "End of line"]
    ["C-x C-s" (λ (m e) (save m)) #:doc "Save file"
               #:when (λ (ctx) (modified? ctx))]))

;; Dispatch keys
(dispatch-key my-keymap state key-event model)
```

### Widgets

```racket
;; Text input
(define input (text-input-init
               #:placeholder "Enter name..."
               #:prompt "> "
               #:validation validate-not-empty))
(text-input-update input event)
(text-input-view input width)
(text-input-value input)

;; Textarea
(define editor (textarea-init #:width 60 #:height 20))
(textarea-update editor event)
(textarea-view editor)

;; Viewport (scrollable)
(define scroll (viewport-init #:width 40 #:height 10 #:content long-text))
(viewport-update scroll event)
(viewport-view scroll)

;; List selection
(define menu (list-init
              #:items (list (list-item "Open" 'open #t (hash))
                           (list-item "Save" 'save #t (hash)))))
(list-update menu event)
(list-view menu)
(list-selected-item menu)
```

### Commands

```racket
;; No command
none

;; Quit the program
(quit)

;; Send async message
(send-msg my-message)

;; Batch multiple commands
(batch cmd1 cmd2 cmd3)
```

## Text Measurement

The framework correctly handles ANSI escape codes and wide characters:

```racket
(text-width "hello")           ; => 5
(text-width "\e[31mred\e[0m")  ; => 3 (ANSI stripped)
(text-width "日本語")          ; => 6 (wide chars = 2 each)

(wrap-text "long text..." 40)  ; => list of wrapped lines
(truncate-text "too long" 5)   ; => "too l"
(truncate-text "too long" 5 "…")  ; => "too …"
```

## Running the Demo

```bash
racket src/tui/examples/demo.rkt
```

## Testing

```bash
raco test src/tui/
# 283 tests passed
```

## Comparison with Bubble Tea/Lipgloss

| Feature | Bubble Tea/Lipgloss | This Framework |
|---------|---------------------|----------------|
| Elm architecture | ✓ | ✓ |
| Styling (colors, attrs) | ✓ | ✓ |
| Borders & padding | ✓ | ✓ |
| Flexbox layout | ✓ | ✓ |
| Text input widget | ✓ | ✓ |
| Textarea widget | ✓ | ✓ |
| Viewport/scrolling | ✓ | ✓ |
| List selection | ✓ | ✓ |
| Key sequences | ✓ | ✓ |
| Kitty keyboard protocol | ✓ | ✓ |
| Mouse support | ✓ | ✓ |
| Diff rendering | ✓ | ✓ |
| ANSI-aware text width | ✓ | ✓ |
