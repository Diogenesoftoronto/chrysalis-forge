---
name: building-racket-clis
description: Builds Racket command-line applications with proper argument parsing, subcommands, and packaging. Use when creating CLI tools, adding command-line options, or packaging Racket executables.
---

# Building Racket CLI Applications

## Quick Start

```racket
#lang racket
(require racket/cmdline)

(define verbose (make-parameter #f))

(command-line
 #:program "my-cli"
 #:once-each
 [("-v" "--verbose") "Enable verbose output" (verbose #t)]
 #:args (filename)
 (when (verbose) (displayln "Processing..."))
 (displayln filename))
```

## Command-Line Parsing with `racket/cmdline`

### Basic Flags and Arguments

```racket
(require racket/cmdline)

(define output-file (make-parameter "out.txt"))
(define count (make-parameter 1))

(command-line
 #:program "tool"
 #:once-each
 [("-o" "--output") file "Output file path" (output-file file)]
 [("-n" "--count") n "Number of iterations" (count (string->number n))]
 #:once-any
 [("--json") "Output as JSON" (format-param 'json)]
 [("--csv") "Output as CSV" (format-param 'csv)]
 #:multi
 [("-i" "--include") path "Include additional path" (includes (cons path (includes)))]
 #:args (input-file . rest-files)
 (process-files (cons input-file rest-files)))
```

### Flag Types

| Directive | Purpose |
|-----------|---------|
| `#:once-each` | Flag can appear once |
| `#:once-any` | Only one of these flags allowed |
| `#:multi` | Flag can repeat, accumulates values |
| `#:final` | Stops processing after this flag |
| `#:args` | Positional arguments pattern |
| `#:usage-help` | Custom usage message |

### Subcommands Pattern

```racket
#lang racket
(require racket/cmdline)

(define (cmd-init args)
  (command-line #:program "mycli init"
                #:argv args
                #:args () (displayln "Initialized!")))

(define (cmd-run args)
  (define watch (make-parameter #f))
  (command-line #:program "mycli run"
                #:argv args
                #:once-each [("-w" "--watch") "Watch mode" (watch #t)]
                #:args (file) (run-file file (watch))))

(define (main)
  (define args (current-command-line-arguments))
  (when (zero? (vector-length args))
    (displayln "Usage: mycli <command> [options]")
    (displayln "Commands: init, run")
    (exit 1))
  (match (vector-ref args 0)
    ["init" (cmd-init (vector-drop args 1))]
    ["run" (cmd-run (vector-drop args 1))]
    [cmd (eprintf "Unknown command: ~a~n" cmd) (exit 1)]))

(module+ main (main))
```

## Packaging as Executable

### Method 1: raco exe (Standalone Binary)

```bash
# Create standalone executable
raco exe -o my-cli main.rkt

# Create distribution with dependencies
raco distribute dist-folder my-cli
```

### Method 2: Launcher via info.rkt (Installed with Package)

In `info.rkt`:
```racket
#lang info
(define collection "my-package")
(define deps '("base"))

;; Define CLI launchers
(define racket-launcher-names '("my-cli" "my-cli-admin"))
(define racket-launcher-libraries '("main.rkt" "admin.rkt"))
```

Install with:
```bash
raco pkg install --link .
# Now 'my-cli' is available in PATH
```

### Method 3: GraalVM Native Image (Advanced)

```bash
# Compile to bytecode
raco make main.rkt
# Use racket-native or wrap in GraalVM (experimental)
```

## Interactive Input

```racket
;; Simple prompt
(define (prompt msg)
  (display msg)
  (flush-output)
  (read-line))

;; Password input (no echo - requires terminal)
(define (prompt-password msg)
  (display msg)
  (flush-output)
  (system "stty -echo")
  (define pw (read-line))
  (system "stty echo")
  (newline)
  pw)

;; Confirmation
(define (confirm? msg)
  (define response (prompt (format "~a [y/N]: " msg)))
  (member (string-downcase (string-trim response)) '("y" "yes")))
```

## Output Formatting

### Colored Output

```racket
(require racket/format)

(define (color code text)
  (format "\033[~am~a\033[0m" code text))

(define (red text) (color 31 text))
(define (green text) (color 32 text))
(define (yellow text) (color 33 text))
(define (blue text) (color 34 text))
(define (bold text) (color 1 text))

(displayln (green "✓ Success"))
(displayln (red "✗ Error"))
```

### Progress Indicators

```racket
(define (with-spinner msg thunk)
  (define frames '("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏"))
  (define done? (box #f))
  (define spinner-thread
    (thread
     (λ ()
       (let loop ([i 0])
         (unless (unbox done?)
           (printf "\r~a ~a" (list-ref frames (modulo i 10)) msg)
           (flush-output)
           (sleep 0.1)
           (loop (add1 i)))))))
  (define result (thunk))
  (set-box! done? #t)
  (thread-wait spinner-thread)
  (printf "\r✓ ~a~n" msg)
  result)
```

## Exit Codes

```racket
;; Standard exit codes
(define EXIT-SUCCESS 0)
(define EXIT-ERROR 1)
(define EXIT-USAGE 64)    ; EX_USAGE from sysexits.h
(define EXIT-DATAERR 65)  ; EX_DATAERR
(define EXIT-NOINPUT 66)  ; EX_NOINPUT

(define (die! msg [code EXIT-ERROR])
  (eprintf "Error: ~a~n" msg)
  (exit code))

;; Usage
(unless (file-exists? input-file)
  (die! (format "File not found: ~a" input-file) EXIT-NOINPUT))
```

## Environment Variables

```racket
;; Reading
(define api-key (getenv "API_KEY"))
(define debug? (equal? (getenv "DEBUG") "1"))
(define home (or (getenv "HOME") (find-system-path 'home-dir)))

;; With defaults
(define port (string->number (or (getenv "PORT") "8080")))

;; Setting (for child processes)
(putenv "MY_VAR" "value")
```

## Configuration Files

### XDG-Compliant Config Location

```racket
(define (config-dir)
  (or (getenv "XDG_CONFIG_HOME")
      (build-path (find-system-path 'home-dir) ".config")))

(define (app-config-path app-name)
  (build-path (config-dir) app-name "config.toml"))
```

### Simple Config Loading

```racket
(require json)

(define (load-config path)
  (if (file-exists? path)
      (with-input-from-file path read-json)
      (hash)))

(define (save-config path data)
  (make-parent-directory* path)
  (with-output-to-file path
    #:exists 'replace
    (λ () (write-json data))))
```

## Testing CLIs

```racket
#lang racket
(require rackunit)

;; Capture stdout/stderr
(define (capture-output thunk)
  (define out (open-output-string))
  (define err (open-output-string))
  (parameterize ([current-output-port out]
                 [current-error-port err])
    (thunk))
  (values (get-output-string out)
          (get-output-string err)))

;; Test CLI with args
(define (run-cli-test args)
  (parameterize ([current-command-line-arguments (list->vector args)])
    (capture-output main)))

(test-case "help flag shows usage"
  (define-values (out err) (run-cli-test '("--help")))
  (check-regexp-match #rx"Usage:" out))
```

## Best Practices

1. **Use parameters** for configuration, not global variables
2. **Validate inputs early** with clear error messages
3. **Support `--help`** automatically via command-line
4. **Use exit codes** consistently (0 = success)
5. **Write to stderr** for errors and diagnostics
6. **Support `--version`** for installed tools
7. **Handle signals** gracefully when possible

```racket
;; Version flag
(command-line
 #:program "my-cli"
 #:once-each
 [("--version") "Show version" 
  (displayln "my-cli v1.0.0") (exit 0)]
 ...)
```
