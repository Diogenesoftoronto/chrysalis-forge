# Agent Guidance: GUI Module

The Chrysalis Forge GUI is built using `racket/gui`.

## Key Components

- **main-gui.rkt**: Main application window with chat interface, model/mode selection, and session management

## Architecture

1. **Main Frame**: Top-level window with menu bar
2. **Toolbar Panel**: Model selector, mode selector, session display, cost/token stats
3. **Chat Display**: Read-only text editor for conversation history
4. **Input Area**: Multi-line text input with Send/Attach buttons

## Threading Model

- GUI runs on the main thread (eventspace)
- LLM calls run in background threads via `thread`
- Use `queue-callback` to update UI from background threads

## Adding New Features

1. **New Menu Items**: Add to the appropriate menu in the Menu Bar section
2. **Toolbar Controls**: Add to `toolbar-panel` with proper alignment
3. **New Dialogs**: Follow the pattern of `new-session-dialog` and `switch-session-dialog`

## Running

```bash
racket main.rkt --gui
```

---

## Visual Enhancement Modules

The GUI has been enhanced with the following modular components:

### Theme System (`theme-system.rkt`)
Comprehensive theme management with multiple built-in themes.
```racket
(require "theme-system.rkt")
(load-theme 'dark)              ; Load theme: dark, light, cyberpunk, dracula, solarized-dark/light
(theme-ref 'bg)                 ; Get color% object for key
(theme-ref 'accent)             ; Keys: bg, fg, accent, surface, error, success, warning, info, etc.
(save-theme-preference! 'dracula)  ; Persist to ~/.config/chrysalis-forge/theme.json
(list-themes)                   ; List available theme names
```

### Chat Widget (`chat-widget.rkt`)
Enhanced chat interface with message bubbles and streaming support.
```racket
(require "chat-widget.rkt")
(define chat (make-chat-widget parent))
(send chat append-message 'user "Hello!")
(send chat append-message 'assistant "Hi there!")
(send chat append-streaming-chunk "Streaming...")  ; For LLM streaming
(send chat finish-streaming)
(send chat clear-messages)
(send chat get-history)  ; Returns list of (role . content)
```
- Message roles: `'user`, `'assistant`, `'system`, `'tool`
- Role icons: 👤 (user), 🤖 (assistant), ⚙ (system), 🔧 (tool)
- Features: timestamps, copy button per message, code block highlighting, streaming cursor

### Widget Framework (`widget-framework.rkt`)
Modern styled widget wrappers with hover effects.
```racket
(require "widget-framework.rkt")
(make-styled-button parent "Click Me" callback #:style 'primary)
(make-styled-text-field parent #:placeholder "Enter text...")
(apply-theme! frame 'dark)  ; Refresh all widget colors
```
Classes: `styled-button%`, `styled-text-field%`, `styled-choice%`, `styled-panel%`, `styled-message%`

### Notification System (`notification-system.rkt`)
Toast notifications that slide in from top-right.
```racket
(require "notification-system.rkt")
(define nm (make-notification-manager parent))
(show-notification! nm 'success "File saved!" #:duration 3000)
(show-notification! nm 'error "Connection failed")
(show-notification! nm 'warning "Low memory")
(show-notification! nm 'info "Tip: Use Ctrl+Enter to send")
```
- Types: `'info` (ℹ blue), `'success` (✓ green), `'warning` (⚠ yellow), `'error` (✗ red)
- Auto-dismiss after duration, click to dismiss early
- Queue system for multiple notifications (max 5 visible)

### Animation Engine (`animation-engine.rkt`)
Smooth animations with easing functions.
```racket
(require "animation-engine.rkt")
(define am (make-animation-manager))
(animate! am target 'x 0 100 #:duration 300 #:easing 'ease-out-quad #:on-complete proc)
```
Easing functions: `ease-linear`, `ease-in-quad`, `ease-out-quad`, `ease-in-out-quad`, `ease-in-cubic`, `ease-out-cubic`

---

## Module Dependency Graph

```
main-gui.rkt
├── theme-system.rkt      ; Theme colors and persistence
├── chat-widget.rkt       ; Enhanced chat display
│   └── theme-system.rkt
├── widget-framework.rkt  ; Modern styled widgets
│   └── theme-system.rkt
├── notification-system.rkt ; Toast notifications
│   └── theme-system.rkt
└── animation-engine.rkt  ; Smooth animations
```

## Integration Notes

When updating main-gui.rkt to use these modules:

1. Replace hardcoded colors with `(theme-ref 'key)`:
   - `bg-color` → `(theme-ref 'bg)`
   - `fg-color` → `(theme-ref 'fg)`
   - `accent-color` → `(theme-ref 'accent)`

2. Create notification manager after main-frame:
   ```racket
   (define notif-manager (make-notification-manager main-frame))
   ```

3. Use for user feedback:
   ```racket
   (show-notification! notif-manager 'success "Message sent!")
   (show-notification! notif-manager 'error "Failed to connect")
   ```

4. Add theme selector to Tools menu for runtime switching.
