# Agent Guidance: TUI Module

The TUI framework is a Bubble Tea-style terminal UI system with Lipgloss-like styling.

## Architecture

**Elm-style loop**: `init` → `model` → `view` → render → events → `update` → loop

- **Model**: Application state (use structs, immutable)
- **Update**: `(model, event) → (values model cmd)`
- **View**: `(model, size) → doc`
- **Cmd**: Async effects that produce messages

## Key Modules

| Module | Purpose |
|--------|---------|
| `program.rkt` | Elm-style program runner, event loop |
| `event.rkt` | Event structs (key, mouse, paste, resize) |
| `keymap.rkt` | Declarative key bindings with sequences |
| `style.rkt` | Lipgloss-style styling (colors, borders, padding) |
| `doc.rkt` | Composable document tree (txt, row, col, box) |
| `layout.rkt` | Flexbox-like constraint solver |
| `text/measure.rkt` | ANSI-aware text width/height |
| `text/buffer.rkt` | Gap-buffer-style text editing |
| `widgets/*.rkt` | Reusable components (input, textarea, list, viewport) |
| `render/screen.rkt` | Diff-based terminal rendering |

## Common Patterns

### Creating a Widget

Widgets follow the same pattern as the main app:

```racket
(struct my-widget-model (field1 field2 focused?) #:transparent)

(define (my-widget-init #:option [opt default]) 
  (my-widget-model ...))

(define (my-widget-update model event)
  (match event
    [(key-event 'up _ _ _) ...]
    [_ (values model '())]))

(define (my-widget-view model)
  (col (txt "...")))
```

### Style Keywords

Use `#:bold`, `#:dim`, `#:italic` etc. (NOT `#:bold?`):

```racket
(style-set empty-style
           #:fg 'cyan
           #:bold #t      ; NOT #:bold?
           #:padding '(1 1 1 1))
```

### Document Composition

```racket
(col                           ; vertical stack
 (txt "Header" header-style)
 (vspace 1)
 (row                          ; horizontal
  (doc-block widget1 box-style)
  (hspace 2)
  (doc-block widget2 box-style)))
```

### Text Width

**Never use `string-length` for layout.** Always use:

```racket
(text-width str)      ; handles ANSI + wide chars
(wrap-text str width) ; word wrap
```

### Events

Key events use sets for modifiers:

```racket
(key-event 'enter #f (set 'ctrl) #"")  ; Ctrl+Enter
(key-event #f #\a (set) #"a")          ; Just 'a'
```

Check modifiers: `(ctrl? evt)`, `(alt? evt)`, `(shift? evt)`

### Commands

```racket
none              ; no effect
(quit)            ; exit program
(send-msg m)      ; async message
(batch c1 c2)     ; multiple commands
```

## Adding New Features

1. **New widget**: Follow `text-input.rkt` as template
2. **New style property**: Add to `style` struct in `style.rkt`, update `style-set` and `style-render`
3. **New event type**: Add struct to `event.rkt`, handle in `input/parse.rkt`
4. **New layout node**: Add to `doc.rkt`, handle in `layout.rkt`

## Testing

Each module has a `(module+ test ...)` section:

```bash
raco test src/tui/            # All tests
raco test src/tui/style.rkt   # Single module
```

## Key Design Constraints

1. **Immutability**: All model updates return new values
2. **Functional style**: No side effects in update/view
3. **Composability**: Widgets are just (init/update/view) tuples
4. **ANSI correctness**: Always strip ANSI for width calculations
