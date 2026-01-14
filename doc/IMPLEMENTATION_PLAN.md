# Documentation and Feature Implementation Plan

This document outlines the plan to align documentation with implementation and add missing features.

---

## 1. Fix USAGE.md: Budget/Timeout Documentation

### Problem
`--budget` and `--timeout` are documented as CLI flags but only work as environment variables or `/config` commands.

### Current State
- **Implemented**: Environment variables `BUDGET` and `TIMEOUT`, `/config budget` and `/config timeout` commands
- **Documented**: CLI flags `--budget` and `--timeout` (incorrect)

### Tasks

#### 1.1 Update USAGE.md Examples
**File**: `doc/USAGE.md`
**Location**: Lines ~445-455 (Budget and Timeout Control section)

**Changes**:
- Replace CLI flag examples with environment variable examples
- Add `/config` command examples
- Add note about CLI flag support being planned

**Example Fix**:
```markdown
### Budget and Timeout Control

For production use, set limits using environment variables or the `/config` command:

```bash
# Using environment variables
BUDGET=2.00 chrysalis "Deep codebase analysis"
TIMEOUT=600 chrysalis "Comprehensive test generation"

# Or set interactively
chrysalis -i
/config budget 2.00
/config timeout 600
```

**Note**: CLI flags `--budget` and `--timeout` are planned for a future release. Currently, use environment variables or the `/config` command.
```

#### 1.2 Update README.md
**File**: `README.md`
**Location**: Lines ~112-117 (Configuration section)

**Changes**:
- Update configuration examples to show environment variables
- Remove or clarify CLI flag references

---

## 2. Add Missing REPL Commands

### Problem
Three REPL commands are documented but not implemented: `/mode`, `/stats`, `/evolve`

### Current State
- **Documented**: `/mode code`, `/mode architect`, `/stats`, `/evolve`
- **Implemented**: None of these commands exist in `main.rkt`

### Tasks

#### 2.1 Implement `/mode` Command
**File**: `main.rkt`
**Location**: `handle-slash-command` function (around line 406)

**Implementation**:
```racket
["mode"
 (define rest (if (>= (string-length input) 6)
                  (string-trim (substring input 6))
                  ""))
 (define mode-str (if (> (string-length rest) 0)
                      rest
                      ""))
 (cond
   [(string=? mode-str "")
    (printf "Current mode: ~a\n" (Ctx-mode (ctx-get-active)))
    (printf "Available modes: ask, architect, code, semantic\n")
    (printf "Usage: /mode <mode-name>\n")]
   [(member mode-str '("ask" "architect" "code" "semantic"))
    (handle-new-session "cli" mode-str)
    (printf "Switched to ~a mode\n" mode-str)]
   [else
    (printf "Invalid mode: ~a\n" mode-str)
    (printf "Available modes: ask, architect, code, semantic\n")])]
```

**Update help text** (line ~412):
Add `/mode <name>` to the help message

#### 2.2 Implement `/stats` Command
**File**: `main.rkt`
**Location**: `handle-slash-command` function

**Dependencies**: 
- `src/stores/eval-store.rkt` - `get-profile-stats` function (may need to be created)
- `profile_stats` tool already exists, can reuse logic

**Implementation**:
```racket
["stats"
 (with-handlers ([exn:fail? (λ (e)
                             (eprintf "[ERROR] Failed to get stats: ~a\n" (exn-message e)))])
   (define stats-json (profile_stats '()))
   (define stats (string->jsexpr stats-json))
   (if (null? stats)
       (printf "No profile statistics available yet.\n")
       (begin
         (printf "\nProfile Performance Statistics:\n")
         (for ([profile stats])
           (define name (hash-ref profile 'profile "unknown"))
           (define success-rate (hash-ref profile 'success_rate 0.0))
           (define avg-duration (hash-ref profile 'avg_duration 0.0))
           (define avg-cost (hash-ref profile 'avg_cost 0.0))
           (define task-count (hash-ref profile 'task_count 0))
           (printf "\n  Profile: ~a\n" name)
           (printf "    Success rate: ~a%\n" (* success-rate 100))
           (printf "    Average duration: ~as\n" avg-duration)
           (printf "    Average cost: $~a\n" (real->decimal-string avg-cost 4))
           (printf "    Tasks completed: ~a\n" task-count))
         (printf "\n"))))]
```

**Update help text**: Add `/stats` to help message

#### 2.3 Implement `/evolve` Command
**File**: `main.rkt`
**Location**: `handle-slash-command` function

**Implementation**:
```racket
["evolve"
 (define rest (if (>= (string-length input) 8)
                  (string-trim (substring input 8))
                  ""))
 (if (string=? rest "")
     (displayln "Usage: /evolve \"Your feedback about what to improve\"")
     (begin
       (printf "Triggering GEPA evolution with feedback: ~a\n" rest)
       (with-handlers ([exn:fail? (λ (e)
                                   (eprintf "[ERROR] Evolution failed: ~a\n" (exn-message e)))])
         ;; Use ctx_evolve tool logic
         (define result (gepa-evolve! rest (model-param)))
         (printf "Evolution complete. New prompt optimized.\n"))))]
```

**Update help text**: Add `/evolve "feedback"` to help message

#### 2.4 Update Documentation
**File**: `doc/USAGE.md`
**Location**: Lines ~98-117 (REPL commands section)

**Changes**:
- Verify all three commands are properly documented
- Add examples for each command
- Ensure accuracy of descriptions

---

## 4. Document Existing Features

### Problem
Several implemented features lack documentation: GUI mode, MCP integration, service tools, `/attach`, `/image`, `/judge`

### Tasks

#### 4.1 Document GUI Mode
**File**: `doc/USAGE.md`
**Location**: After "IDE Integration" section (around line ~165)

**Content to Add**:
```markdown
### GUI Mode

Chrysalis Forge includes a graphical user interface for visual interaction:

```bash
chrysalis --gui
```

The GUI provides:
- Visual conversation history
- Tool call visualization
- Session management
- Configuration panel
- Real-time token usage and cost tracking

This is useful for users who prefer a visual interface over the command-line REPL.
```

**File**: `README.md`
**Location**: After "CLI Tasks" section

**Content to Add**:
```markdown
### GUI Mode
```bash
chrysalis --gui
```
```

#### 4.2 Document MCP Integration
**File**: `doc/USAGE.md`
**Location**: After "The Tool System" section (around line ~280)

**Content to Add**:
```markdown
### MCP (Model Context Protocol) Integration

Chrysalis Forge supports the Model Context Protocol, allowing you to dynamically connect external tool servers:

```
[USER]> Use add_mcp_server to connect to a filesystem MCP server
[AGENT uses add_mcp_server tool]
```

The agent can automatically discover and use tools from connected MCP servers. This enables:
- Extending functionality without code changes
- Integrating with external services
- Sharing tools across different agent instances

**Example**: Connect to a filesystem MCP server:
```
add_mcp_server with name="fs" command="npx" args=["-y", "@modelcontextprotocol/server-filesystem", "/path/to/allowed/dir"]
```

Once connected, all tools from the MCP server become available to the agent automatically.
```

**File**: `doc/API.md`
**Location**: Add new section "MCP Integration"

**Content**: Document the `add_mcp_server` tool, how MCP clients are managed, and how tools are registered.

#### 4.3 Document Service Management Tools
**File**: `doc/USAGE.md`
**Location**: In "The Tool System" section, add subsection

**Content to Add**:
```markdown
### Service Management

The agent can manage background services (requires security level 2+):

- `service_start` - Start a background service
- `service_stop` - Stop a running service  
- `service_list` - List all managed services

These tools are useful for managing long-running processes, databases, or other services that the agent needs to interact with.
```

**File**: `doc/API.md`
**Location**: In tools section

**Content**: Document the service management tools with parameters and examples.

#### 4.4 Document File/Image Attachment Commands
**File**: `doc/USAGE.md`
**Location**: In REPL commands section (around line ~98)

**Content to Add**:
```markdown
- `/attach <path>` - Attach a file to the next message (content will be included)
- `/image <path>` - Attach an image to the next message (for vision models)
```

**Example**:
```markdown
### Attaching Files and Images

You can attach files or images to your messages:

```
[USER]> /attach src/main.rkt
Attached file: src/main.rkt

[USER]> Explain this code
[AGENT receives the file content automatically]
```

For vision-capable models, attach images:

```
[USER]> /image screenshot.png
Attached image: screenshot.png

[USER]> What's shown in this screenshot?
[AGENT uses vision model to analyze the image]
```
```

#### 4.5 Document `/judge` Command
**File**: `doc/USAGE.md`
**Location**: In REPL commands section

**Content to Add**:
```markdown
- `/judge` - Toggle LLM Security Judge on/off (shows current status)
```

**File**: `doc/USAGE.md`
**Location**: In "Understanding Modes and Security" section

**Content to Add**:
```markdown
You can toggle the LLM Security Judge during a session:

```
[USER]> /judge
LLM Security Judge: ENABLED

[USER]> /judge
LLM Security Judge: DISABLED
```

The judge status persists for the current session.
```

#### 4.6 Update Tool Reference
**File**: `README.md`
**Location**: Tool categories section

**Content to Add**:
- Add "MCP Tools" category
- Add "Service Management" category
- Update tool counts if needed

---

## Implementation Order

1. **Phase 1: Documentation Fixes** (Low risk, immediate value)
   - 1.1: Fix USAGE.md budget/timeout examples
   - 1.2: Update README.md configuration section
   - 4.1-4.6: Document existing features

2. **Phase 2: REPL Command Implementation** (Medium complexity)
   - 2.1: Implement `/mode` command
   - 2.2: Implement `/stats` command  
   - 2.3: Implement `/evolve` command
   - 2.4: Update documentation

## Testing Checklist

### For Documentation Fixes
- [ ] Verify all examples in USAGE.md work as documented
- [ ] Check that environment variable examples are correct
- [ ] Ensure all new documentation sections are accurate

### For REPL Commands
- [ ] Test `/mode` with all valid modes (ask, architect, code, semantic)
- [ ] Test `/mode` with invalid mode (error handling)
- [ ] Test `/mode` without arguments (shows current mode)
- [ ] Test `/stats` when no data exists
- [ ] Test `/stats` when data exists
- [ ] Test `/evolve` with valid feedback
- [ ] Test `/evolve` without arguments (shows usage)
- [ ] Verify help text includes all new commands
- [ ] Test that mode changes persist across turns

### For Feature Documentation
- [ ] Verify GUI mode works as documented
- [ ] Test MCP integration examples
- [ ] Verify service tools work as documented
- [ ] Test file/image attachment commands
- [ ] Verify `/judge` toggle works

## Notes

- The `/mode` command should use `handle-new-session` to ensure proper context switching
- The `/stats` command may need to call the `profile_stats` tool or directly access eval-store
- The `/evolve` command should use the existing `gepa-evolve!` function
- All new commands should follow the existing error handling patterns in `handle-slash-command`
- Documentation should include examples for each new feature
