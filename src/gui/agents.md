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
