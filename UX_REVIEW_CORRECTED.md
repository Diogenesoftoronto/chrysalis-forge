# Chrysalis Forge UX Review - Corrected

## Executive Summary

You're right - my initial assessment was off. The models work fine, but the specific friction points you mentioned are real issues that affect daily usage.

---

## Confirmed Problems

### 1. `/models` Fuzzy Search Doesn't Work 🔴

**Issue**: The `/models <query>` command exists but doesn't actually find models when you search.

**Root Cause Analysis**:

In `src/core/commands.rkt:442-458`:
- Listing without query (`/models`) fetches from API endpoint via `fetch-models-from-endpoint`
- Searching with query (`/models gpt`) calls `fuzzy-search-models` which searches the **local model registry**

The problem: The model registry is never initialized in the REPL flow! I searched for `init-model-registry` calls and found **zero** in `commands.rkt`, `repl.rkt`, or `main-gui.rkt`.

`fuzzy-search-models` (defined in `src/llm/model-registry.rkt:543-563`) only searches models loaded into the hash registry. If the registry is empty, it returns nothing.

**User Experience**:
```
[USER]> /models gpt
Searching models for: gpt
No matching models found.
```

When there should be `gpt-4o`, `gpt-4o-mini`, etc.

**Fix**: Initialize model registry on first `/models` call or during REPL startup.

---

### 2. No Command History Stack 🔴

**Issue**: No way to navigate, repeat, or queue previously sent user commands.

**Evidence**:
- `Ctx-history` exists but stores LLM conversation messages, not user commands
- Search for `command-history` or `command-stack` returns nothing relevant
- No arrow key navigation through previous commands
- No `/history` command

**User Impact**:
- Cannot repeat a complex command without retyping
- Cannot queue up a task while LLM is working on current one
- Frustrating for iterative workflows where you try variations

**Missing Features**:
```
# Should have:
[USER]> <up arrow>     # Navigate command history
[USER]> /history         # Show last 10 commands
[USER]> /queue analyze file.txt   # Queue for next
[USER]> /queue list     # Show queued tasks
```

**Fix**: Add command history storage and navigation:
- Store all non-slash user commands in a list
- Implement arrow key navigation in `read-multiline-input` (repl.rkt)
- Add `/history` and `/queue` commands

---

### 3. No Command Queue System 🔴

**Issue**: Cannot queue tasks for the agent to do after completing current work.

**User Impact**:
- Must wait for LLM to finish before typing next task
- Can't plan multi-step workflows efficiently
- Inefficient for "do X, then do Y" workflows

**Proposed Design**:
```
[USER]> /queue read README.md
[USER]> /queue summarize the code in src/core/
[USER]> /queue list
Queued:
  1. read README.md
  2. summarize code in src/core/

[USER]> /queue clear   # Clear queue
[USER]> /queue pop     # Remove top item
```

**Implementation Location**: New file `src/core/command-queue.rkt`

---

## Secondary Observations

### 4. Fuzzy Search Algorithm Could Be Better

Current implementation (model-registry.rkt:552-559):
- Exact match: score 0
- Prefix match: score 10
- Contains match: score 20
- Levenshtein: `50 + distance*2`

**Issue**: The score gap between prefix (10) and contains (20) is too small. "gpt-4" should rank much higher than "gpt-mini".

**Improvement**: Weight prefix matches more heavily:
```racket
[(string-prefix? id-lower query-lower) 5]  ; Was 10, now 5 (better)
[(string-contains? id-lower query-lower) 25]  ; Was 20, now worse
```

---

## Implementation Plan

### Priority 1: Fix `/models` Fuzzy Search

**File**: `src/core/repl.rkt`

**Change**: Initialize model registry on REPL startup
```racket
;; After (verify-env! #:fail #f)
(when (and env-api-key (base-url-param))
  (with-handlers ([exn:fail? (λ (e)
                                 (log-debug 1 'repl "Failed to init model registry: ~a" (exn-message e)))])
    (init-model-registry! #:api-key env-api-key #:api-base (base-url-param))))
```

**File**: `src/core/commands.rkt`

**Change**: Ensure registry is initialized before search
```racket
["models"
 (define rest ...)
 (with-handlers (...)
   (when (and (string=? rest "") (hash-empty? model-registry))  ; Check if empty
     (init-model-registry! #:api-key api-key #:api-base (base-url-param)))
   ;; Rest of existing logic
   )]
```

---

### Priority 2: Command History

**File**: `src/core/repl.rkt`

**Add**:
```racket
(define command-history (make-parameter '()))
(define command-history-index (make-parameter 0))
(define MAX-HISTORY 100)

(define (add-to-command-history! cmd)
  (define trimmed (string-trim cmd))
  (when (and (> (string-length trimmed) 0)
             (not (string-prefix? trimmed "/")))  ; Don't save slash commands
    (let ([current (command-history)])
      (command-history
       (take (cons trimmed current) MAX-HISTORY))
      (command-history-index 0))))

(define (navigate-history direction)
  (define hist (command-history))
  (when (not (null? hist))
    (define new-idx (max 0 (min (sub1 (length hist))
                                   (+ (command-history-index) direction))))
    (command-history-index new-idx)
    (list-ref hist new-idx)))

;; In repl-loop, call add-to-command-history! after successful processing
```

**File**: `src/core/repl.rkt` - `read-multiline-input`

**Add** arrow key handling:
```racket
[(char=? c #\u001B)  ; ESC sequence start
 (define next (read-char))
 (when (char=? next #\[)
   (define arrow (read-char))
   (match arrow
     [#\A  ; Up arrow
      (when (> (command-history-index) 0)
        (let ([prev (navigate-history -1)])
          (display (string-append "\r\033[K[USER]> " prev))
          (flush-output)))]
     [#\B  ; Down arrow
      (let ([next (navigate-history 1)]
        (display (string-append "\r\033[K[USER]> " next))
        (flush-output))]))]
```

**Add** slash command:
```racket
["history"
 (define hist (command-history))
 (if (null? hist)
     (displayln "No command history.")
     (for ([cmd (in-list (reverse hist))]
           [i (in-naturals 1)])
       (printf "  ~a. ~a~n" i cmd)))]
```

---

### Priority 3: Command Queue

**File**: New `src/core/command-queue.rkt`

```racket
#lang racket/base

(provide add-to-queue!
         get-next-queued!
         list-queue!
         clear-queue!
         remove-queue-item!)

(define command-queue (make-parameter '()))
(define MAX-QUEUE 20)

(define (add-to-queue! task)
  (let ([current (command-queue)])
    (if (>= (length current) MAX-QUEUE)
        (displayln "Queue is full. Use /queue list to see queued tasks.")
        (command-queue (append current (list task))))))

(define (get-next-queued!)
  (define current (command-queue))
  (if (null? current)
      #f
      (begin
        (define task (first current))
        (command-queue (rest current))
        task)))

(define (list-queue!)
  (define current (command-queue))
  (if (null? current)
      (displayln "Queue is empty.")
      (begin
        (displayln "Queued tasks:")
        (for ([task (in-list current)]
              [i (in-naturals 1)])
          (printf "  ~a. ~a~n" i task)))))

(define (clear-queue!)
  (command-queue '())
  (displayln "Queue cleared."))

(define (remove-queue-item! index)
  (define current (command-queue))
  (if (and (>= index 0) (< index (length current)))
      (begin
        (command-queue (append (take current index) (drop current (add1 index))))
        (printf "Removed item ~a from queue.~n" index))
      (displayln "Invalid queue index.")))
```

**File**: `src/core/commands.rkt` - Add queue commands

```racket
["queue"
 (define rest (if (>= (string-length input) 7)
                  (string-trim (substring input 7))
                  ""))
 (define parts (if (> (string-length rest) 0)
                   (string-split rest)
                   '()))
 (cond
   [(null? parts)
    (list-queue!)]
   [(equal? (first parts) "clear")
    (clear-queue!)]
   [(equal? (first parts) "pop")
    (define task (get-next-queued!))
    (if task
        (printf "Removed from queue: ~a~n" task)
        (displayln "Queue is empty."))]
   [(and (equal? (first parts) "remove") (= (length parts) 2))
    (remove-queue-item! (string->number (second parts)))]
   [else
    ;; Add to queue
    (define task (string-join parts " "))
    (add-to-queue! task)
    (printf "Added to queue: ~a~n" task)])]
```

**File**: `src/core/repl.rkt` - Auto-process queue

Add queue processing after each turn completes:
```racket
(when (not (null? (command-queue)))
  (define next (get-next-queued!))
  (when next
    (printf "\n[Processing queued task]: ~a\n" next)
    ;; Process as if user typed it
    ))
```

---

## Success Metrics

### Week 1
- ✅ `/models gpt` returns matching models (currently returns "No matching models found")
- ✅ Model registry initialized automatically on `/models` first call

### Week 2
- ✅ Arrow keys navigate through last 100 user commands
- ✅ `/history` shows numbered list of previous commands
- ✅ Can type `/history 3` to re-run command #3

### Week 2-3
- ✅ `/queue <task>` adds to pending queue
- ✅ Queue automatically processed after each LLM turn
- ✅ `/queue list` / `/queue clear` / `/queue pop` all working

---

## Technical Notes

### State Persistence

Both command history and queue should persist to disk:
- History: `~/.agentd/command_history.json`
- Queue: `~/.agentd/queue.json` (maybe - if you want persistent queues across sessions)

### File Locations

- Model registry: `src/llm/model-registry.rkt` - already has fuzzy search
- Command handling: `src/core/commands.rkt` - add /history and /queue
- REPL loop: `src/core/repl.rkt` - add arrow key handling
- New file: `src/core/command-queue.rkt` - queue implementation

---

## Summary

Your identified issues are real and addressable:

1. **`/models` fuzzy search broken** - Registry not initialized, so search always returns empty
2. **No command history** - Missing arrow key navigation and `/history` command
3. **No command queue** - No way to plan multi-step workflows

All three are fixable without architectural changes. The fuzzy search algorithm exists and works—it's just searching an empty registry. Command history and queue are standard REPL features that just need implementation.

Would you like me to implement any of these fixes?
