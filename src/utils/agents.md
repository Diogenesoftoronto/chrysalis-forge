# Agent Guidance: Utilities

Use these utilities to keep the codebase clean and observe best practices.

## Debugging
- Use `log-debug` with appropriate levels (0-2) instead of `printf`.
- `(log-debug 1 'category "Message")`

## Error Handling
- Use the retry logic in `utils-retry.rkt` for flaky operations (like LLM calls or network requests).

## Testing
- When asked to generate tests, refer to `test-gen.rkt` for the underlying logic used by the `generate_tests` tool.

---

## Visual Enhancement Modules

The following modules provide terminal styling and visual feedback for the CLI:

### Terminal Styling (`terminal-style.rkt`)
ANSI color codes, text formatting, and theme support.
```racket
(require "terminal-style.rkt")
(color 'cyan "text")           ; Colored text
(bold "important")             ; Bold text
(error-message "oops")         ; Pre-styled error (red ✗)
(success-message "done")       ; Pre-styled success (green ✓)
(styled text #:fg 'red #:bold? #t)  ; Combined styling
```

### Loading Animations (`loading-animations.rkt`)
Multi-style spinners and progress bars.
```racket
(require "loading-animations.rkt")
(define-values (t id) (start-spinner! "Loading..." #:style 'dots))
(stop-spinner! t)
(with-spinner "Processing" body ...)  ; Scoped spinner

(define pb (make-progress-bar 100 #:label "Downloading"))
(progress-bar-update! pb 50)
(progress-bar-finish! pb)
```
Spinner styles: `'dots`, `'blocks`, `'arrows`, `'clock`, `'bounce`, `'line`, `'circle`, `'square`, `'star`, `'pulse`

### Message Boxes (`message-boxes.rkt`)
Styled terminal message boxes with Unicode borders.
```racket
(require "message-boxes.rkt")
(error-box "Something went wrong" #:suggestions '("Try again" "Check logs"))
(success-box "Operation complete!")
(warning-box "Proceed with caution")
(info-box "Helpful information")
(print-error "Inline error")  ; No box, just styled text
```

### Tool Visualization (`tool-visualization.rkt`)
Visual feedback during tool execution.
```racket
(require "tool-visualization.rkt")
(tool-start! "read_file" #:params (hash 'path "/foo"))
(tool-complete! "read_file" result #:duration-ms 150)
(tool-error! "read_file" "File not found")
(with-tool-viz "my_tool" (hash) body ...)  ; Auto timing/status
```

### Stream Effects (`stream-effects.rkt`)
Streaming output with typewriter effects and markdown formatting.
```racket
(require "stream-effects.rkt")
(stream-typewriter "Hello world" #:delay-ms 20)
(stream-word-by-word "Sentence here" #:delay-ms 50)
(stream-with-formatting "# Header\n**bold** text")  ; Applies terminal styles
```

### Intro Animation (`intro-animation.rkt`)
Animated startup sequence with ASCII art.
```racket
(require "intro-animation.rkt")
(play-intro! #:fast? #f #:skip-checks? #f)
(show-logo #:animated? #t)
(show-system-checks '(("API Key" . ok) ("Model" . ok)))
```

### Status Bar (`status-bar.rkt`)
Persistent bottom status bar for session metrics.
```racket
(require "status-bar.rkt")
(status-bar-show!)
(status-bar-update! #:model "gpt-5.2" #:cost 0.05 #:tokens 1200)
(status-bar-hide!)
```

### Session Summary (`session-summary-viz.rkt`)
Visual session statistics with sparklines and charts.
```racket
(require "session-summary-viz.rkt")
(render-session-summary stats-hash)
(sparkline '(10 20 30 40 50) #:width 20)
(bar-chart '(("tool1" . 5) ("tool2" . 3)))
```

### Theme Manager (`theme-manager.rkt`)
CLI theme configuration and persistence.
```racket
(require "theme-manager.rkt")
(load-cli-theme! 'cyberpunk)
(list-cli-themes)  ; => '(default cyberpunk minimal dracula solarized)
(save-cli-theme-preference! 'dracula)
```
Override via `CHRYSALIS_THEME` environment variable.
