# Chrysalis Forge Usage Guide

A comprehensive guide for developers using Chrysalis Forge, an evolvable, safety-gated Racket agent framework with DSPy-style optimization and self-improving capabilities.

## Table of Contents

1. [Installation](#1-installation)
2. [Quick Start](#2-quick-start)
3. [Configuration Options](#3-configuration-options)
4. [Project Rules](#4-project-rules)
5. [Using Tools](#5-using-tools)
6. [Modes and Security](#6-modes-and-security)
7. [Priority Selection](#7-priority-selection)
8. [Self-Evolution](#8-self-evolution)
9. [Advanced Usage](#9-advanced-usage)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. Installation

### Prerequisites

- **Racket v9.0+** (https://racket-lang.org/)
- Git
- curl (for web search fallback)
- Optional: jj (Jujutsu VCS) for advanced version control

### Clone and Install

```bash
git clone https://github.com/diogenesoft/chrysalis-forge.git
cd chrysalis-forge
raco pkg install --auto
```

This installs two CLI commands:
- `agentd` — Full agent with all tools and modes
- `chrysalis-client` — Lightweight client for remote services

### Environment Variables

Create a `.env` file in the project root (see `.env.example`):

```bash
# Required: OpenAI API Key
OPENAI_API_KEY=sk-...

# Optional: Custom OpenAI-compatible endpoint (LiteLLM, Ollama, etc.)
# OPENAI_API_BASE=http://localhost:1234/v1

# Optional: Exa API for neural web search
# EXA_API_KEY=your_exa_key

# Optional: Service mode (multi-user)
# CHRYSALIS_SECRET_KEY=your-secret-key-here
# CHRYSALIS_HOST=127.0.0.1
# CHRYSALIS_PORT=8080
```

### Required API Keys

| Key | Purpose | Required |
|-----|---------|----------|
| `OPENAI_API_KEY` | LLM intelligence and optimization | **Yes** |
| `EXA_API_KEY` | Neural web search (falls back to curl) | No |
| `CHRYSALIS_SECRET_KEY` | JWT signing for service mode | For `--serve` |

---

## 2. Quick Start

### Interactive Mode

Start an interactive REPL session:

```bash
agentd -i
```

Or use the shorthand:

```bash
chrysalis -i
```

**Basic Conversation:**
```
[USER]> Explain what this project does
[AGENT]> [analyzes codebase and responds]

[USER]> /help
[Shows available commands]

[USER]> /mode code
[Switches to full capabilities mode]

[USER]> /exit
[Exits session]
```

**Using Tools in Interactive Mode:**

The agent automatically uses tools based on your request:

```
[USER]> Search this codebase for all TODO comments
[AGENT uses grep_code tool, returns results]

[USER]> Create a new file at src/utils/helper.rkt with a simple utility
[AGENT uses write_file tool after confirmation]
```

**Switching Modes:**
```
[USER]> /mode ask       # Read-only, no filesystem
[USER]> /mode architect # Can read files for analysis
[USER]> /mode code      # Full capabilities
```

### CLI Tasks

Run a single task and exit:

```bash
# Basic task (read-only)
agentd "Explain what this codebase does"

# Task requiring file writes (security level 2)
agentd --perms 2 "Create a new utility function for parsing JSON"

# Fast execution with specific model
agentd --model gpt-5.2 --priority fast "Quick summary of README.md"

# Use cheap model for budget-conscious tasks
agentd --priority cheap "Analyze this code for issues"

# Initialize agents.md for a project
agentd -i
/init
```

### Service Mode

Run as a multi-user HTTP service:

```bash
# Start service on default port
agentd --serve

# Custom port and host
agentd --serve --serve-port 8080 --serve-host 0.0.0.0

# Run as daemon
agentd --serve --daemonize

# With custom config
agentd --serve --config /path/to/chrysalis.toml
```

Connect with the client:

```bash
chrysalis-client --url http://localhost:8080
# Or with authentication:
chrysalis-client --url http://localhost:8080 --api-key your-jwt-token
```

**Service API Endpoints:**

| Endpoint | Description |
|----------|-------------|
| `POST /auth/register` | Register new user |
| `POST /auth/login` | Login, get JWT token |
| `GET /users/me` | Get current user info |
| `POST /v1/chat/completions` | OpenAI-compatible chat |
| `GET /v1/models` | List available models |
| `GET /v1/sessions` | List user sessions |

### ACP Mode (IDE Integration)

For IDE integration with Amp Code, Zed, and other ACP-compatible editors:

```bash
agentd --acp
```

This starts a JSON-RPC server on stdio for bidirectional communication with the IDE.

---

## 3. Configuration Options

### Command-Line Flags

| Flag | Description | Default |
|------|-------------|---------|
| `--model`, `-m` | LLM model (e.g., `gpt-5.2`, `o1-preview`, `claude-3-opus`) | `gpt-5.2` |
| `--base-url` | Custom API endpoint (LiteLLM, Ollama, local models) | OpenAI |
| `--priority`, `-p` | Execution profile (`best`, `cheap`, `fast`, `verbose`) | `best` |
| `--budget` | Session budget limit in USD | Unlimited |
| `--timeout` | Session time limit | Unlimited |
| `--perms` | Security level (`0`, `1`, `2`, `3`, `god`) | `1` |
| `--debug`, `-d` | Debug verbosity (`0`, `1`, `2`, `verbose`) | `0` |
| `-i`, `--interactive` | Enter interactive REPL mode | — |
| `--acp` | Run ACP Server for IDE integration | — |
| `--serve` | Start HTTP service | — |

### Using Custom LLM Endpoints

**With LiteLLM proxy:**
```bash
OPENAI_API_BASE=http://localhost:4000/v1 agentd -i
```

**With Ollama:**
```bash
agentd --base-url http://localhost:11434/v1 --model llama3.2 -i
```

**With any OpenAI-compatible API:**
```bash
agentd --base-url https://your-proxy.com/v1 --model your-model "Your task"
```

---

## 4. Project Rules

### `.agentd/rules.md`

Create `.agentd/rules.md` in your project root to add project-specific instructions that are automatically appended to the agent's system prompt.

**Example `.agentd/rules.md`:**

```markdown
# Project Rules for MyApp

## Code Style
- Use TypeScript strict mode
- Prefer functional components in React
- Use camelCase for variables, PascalCase for types

## Testing
- All new features need unit tests
- Use Jest with React Testing Library
- Test files go in __tests__ directories

## Git Conventions
- Use conventional commits (feat:, fix:, docs:)
- Keep commits small and atomic
- Always rebase before merging

## Architecture
- API routes in /api directory
- Shared types in /types
- Business logic in /lib
```

### How Rules Are Applied

When the agent starts, it checks for `.agentd/rules.md` in the current working directory. If found, the content is wrapped in `<project_rules>` tags and appended to the system prompt:

```
[Normal system prompt]

<project_rules>
[Your rules.md content]
</project_rules>
```

This ensures project-specific conventions are followed without manual reminders.

---

## 5. Using Tools

Chrysalis Forge provides 25+ built-in tools organized by category.

### File Tools

**`read_file`** — Read file contents
```
Read the contents of src/main.rkt
```

**`write_file`** — Create or overwrite files (requires security level 2+)
```
Create a new file at lib/utils.rkt with a helper function
```

**`patch_file`** — Surgical line-range edits
```
Replace lines 15-20 in config.json with the new settings
```

**`preview_diff`** — Preview changes before applying
```
Show me what changes would be made to package.json
```

**`list_dir`** — Directory listing
```
List all files in the src directory recursively
```

**`grep_code`** — Regex search across files
```
Search for all uses of "define-syntax" in .rkt files
```

### Git Tools

**`git_status`** — Repository status (porcelain format)
```
What's the current git status?
```

**`git_diff`** — Show changes
```
Show me the diff for the last commit
```

**`git_log`** — Commit history
```
Show the last 10 commits
```

**`git_commit`** — Stage and commit (requires level 2+)
```
Commit all changes with message "feat: add new parser"
```

**`git_checkout`** — Branch operations
```
Create and switch to a new branch called feature/auth
```

### Jujutsu (jj) Tools — Next-Gen VCS

Jujutsu is a Git-compatible VCS with powerful undo capabilities. Every operation is tracked and reversible.

**Why jj?**
- **Instant undo**: Any operation can be reversed with `jj_undo`
- **Operation history**: Full audit trail of all VCS operations
- **Time travel**: Restore to any past state with `jj_op_restore`
- **Parallel workspaces**: Work on multiple tasks without stashing

**`jj_status`** — Current working copy state
```
What's the jj status?
```

**`jj_log`** — Commit graph visualization
```
Show the jj commit log
```

**`jj_diff`** — Show changes
```
What changes are in the current jj revision?
```

**`jj_undo`** — Instant rollback (the undo itself can be undone!)
```
Undo the last jj operation
```

**`jj_op_log`** — Operation history
```
Show the jj operation history
```

**`jj_op_restore`** — Time travel to any state
```
Restore to operation abc123 from the op log
```

**`jj_workspace_add`** — Create parallel worktree
```
Create a new workspace at ../feature-branch for the feature revision
```

**`jj_describe`** — Set commit message
```
Set the description for current change to "fix: resolve null pointer"
```

**`jj_new`** — Create new change
```
Create a new change with message "wip: experimenting with parser"
```

### Web Search Tools

**Requires**: `EXA_API_KEY` for full features. Falls back to curl/DuckDuckGo without it.

**`web_search`** — Exa AI semantic search
```
Search the web for "Racket macro best practices"
```

Options:
- `type`: `"auto"` (default), `"neural"`, `"keyword"`, `"fast"`, `"deep"`
- `num_results`: Number of results (default 5)
- `include_text`: Include page text in results

**`web_fetch`** — Fetch URL content via curl
```
Fetch the content from https://docs.racket-lang.org/
```

**`web_search_news`** — Search recent news with date filtering
```
Search for news about "AI agents" from the last 7 days
```

### Evolution Tools

**`evolve_system`** — Trigger GEPA optimization (level 2+)
```
Evolve the system prompt to be more concise
```

**`log_feedback`** — Record task results for learning
```
Log that task-123 succeeded for file-edit category
```

**`suggest_profile`** — Get optimal profile for task type
```
Which profile works best for file editing tasks?
```

**`profile_stats`** — View learning data
```
Show performance statistics for all profiles
```

### Sub-Agent Tools

Spawn parallel tasks with specialized tool profiles.

**`spawn_task`** — Launch parallel sub-agent
```
Spawn a researcher sub-agent to find documentation on Racket contracts
```

Profiles:
- `editor`: File creation/modification (`read_file`, `write_file`, `patch_file`, `preview_diff`, `list_dir`)
- `researcher`: Read-only search (`read_file`, `list_dir`, `grep_code`, `web_search`, `web_fetch`)
- `vcs`: Version control (`git_*`, `jj_*` tools)
- `all`: Full toolkit

**`await_task`** — Wait for completion
```
Wait for task-1 to complete and show results
```

**`task_status`** — Check progress without blocking
```
What's the status of task-1?
```

### Test Generation

**`generate_tests`** — LLM-powered test creation
```
Generate tests for src/parser.rkt using RackUnit
```

The tool:
1. Reads the source file
2. Infers appropriate test framework from file extension
3. Generates comprehensive tests covering edge cases
4. Optionally writes to specified output path

---

## 6. Modes and Security

### Operational Modes

| Mode | Description | Available Tools |
|------|-------------|-----------------|
| `ask` | Basic interaction | `ask_human`, `ctx_evolve`, `run_racket`, workflows |
| `architect` | Read files for analysis | Above + `read_file` |
| `code` | Full capabilities | All tools including write, network, services |
| `semantic` | RDF knowledge graph | Base + RDF tools + memory |

Switch modes in interactive session:
```
/mode code
```

### Security Levels

| Level | Name | Capabilities |
|-------|------|--------------|
| `0` | Read-only | No execution, workspace sandbox only |
| `1` | Sandbox | Safe Racket subset, read filesystem, no network write |
| `2` | Limited I/O | File write (with confirmation), limited network |
| `3` | Full | Full Racket, shell commands (with confirmation) |
| `god` | Unrestricted | Auto-approve all operations (dangerous!) |

**Setting Security Level:**
```bash
# Read-only mode
agentd --perms 0 "Analyze this code"

# Allow file writes (prompts for confirmation)
agentd --perms 2 "Fix the bug in parser.rkt"

# Full access with approval prompts
agentd --perms 3 "Run the test suite"

# Unrestricted (use with caution!)
agentd --perms god "Automate this entire workflow"
```

### LLM Security Judge

Enable an LLM-based security reviewer for sensitive operations:

```bash
export LLM_JUDGE=true
export LLM_JUDGE_MODEL=gpt-5.2
```

When enabled, the judge reviews:
- File writes
- Shell commands
- Network operations
- Any potentially dangerous actions

The judge responds with `[SAFE]` or `[UNSAFE]` after analyzing the operation.

---

## 7. Priority Selection

### Keywords

Use built-in keywords for quick priority setting:

| Keyword | Optimizes For |
|---------|---------------|
| `fast` | Low latency |
| `cheap` | Low cost |
| `best` / `accurate` | High accuracy (default) |
| `verbose` | Detailed explanations |
| `concise` / `compact` | Minimal token usage |

```bash
agentd --priority fast "Quick code review"
agentd --priority cheap "Analyze this large file"
agentd --priority best "Critical production fix"
```

### Natural Language Priority

Describe what you need in plain English:

```bash
# Budget-conscious but accurate
agentd --priority "I'm broke but need precision" "Review this PR"

# Time-sensitive
agentd --priority "I'm in a hurry" "Quick summary"

# Balanced approach
agentd --priority "balance speed and accuracy" "Refactor this module"
```

The system uses **K-Nearest Neighbor search** in a geometric phenotype space to find the elite agent that best matches your stated priorities.

### Autonomous Priority Switching

The agent can change its own priority mid-task using the `set_priority` tool:

```
[AGENT thinking]: This task requires careful analysis, switching to 'best' priority...
[Uses set_priority tool]
```

This enables adaptive behavior where the agent uses fast/cheap settings for simple subtasks and switches to accurate mode for critical decisions.

---

## 8. Self-Evolution

Chrysalis Forge continuously learns and improves through multiple mechanisms.

### Triggering Evolution

**Interactive Command:**
```
/evolve The agent should be more concise and avoid unnecessary explanations
```

**Using the Tool:**
```
Use evolve_system with feedback "Focus more on code quality over speed"
```

**Programmatic:**
```racket
(gepa-evolve! "Make responses more actionable")
```

### Viewing Learning Data

**Interactive Statistics:**
```
/stats
```

**Profile Performance:**
```
Show profile_stats for the editor profile
```

**Eval Store Location:**
```
~/.agentd/evals.jsonl      # Individual task logs
~/.agentd/profile_stats.json # Aggregate statistics
```

### Profile Optimization

The system learns which tool profiles work best for different task types:

1. **Task Execution**: Sub-agent completes task with a specific profile
2. **Result Logging**: `log_feedback` records success/failure
3. **Stats Update**: Aggregate statistics are updated
4. **Profile Suggestion**: `suggest_profile` recommends optimal profile for similar tasks
5. **Evolution**: `evolve_profile!` analyzes and recommends improvements

**Example Flow:**
```
[USER]> Spawn an editor task to fix the bug in parser.rkt
[AGENT uses spawn_task with profile 'editor']
[Task completes successfully]
[AGENT uses log_feedback to record success]

... later ...

[USER]> What profile works best for file editing?
[AGENT uses suggest_profile]
Suggested profile: editor (success rate: 87%)
```

### GEPA Architecture

**GEPA (General Evolvable Prompting Architecture)** evolves system prompts:

1. Current system prompt + feedback → Optimizer LLM
2. Optimizer generates improved prompt
3. New prompt saved as `evo_<timestamp>` context
4. Agent uses evolved prompt in future sessions

**Meta-GEPA** evolves the optimizer itself:
```
/meta_evolve The optimizer should prioritize code safety
```

---

## 9. Advanced Usage

### Parallel Sub-Agents

Spawn multiple tasks that run concurrently:

```
Spawn three parallel tasks:
1. A researcher to find documentation on Racket contracts
2. An editor to create a new module skeleton
3. A VCS agent to check recent changes to related files
```

The agent will:
```racket
(spawn-sub-agent! "Find docs on contracts" run-fn #:profile 'researcher)
(spawn-sub-agent! "Create module skeleton" run-fn #:profile 'editor)
(spawn-sub-agent! "Check VCS history" run-fn #:profile 'vcs)
```

Check status without blocking:
```
What's the status of all spawned tasks?
```

Wait for all to complete:
```
Await all tasks and summarize results
```

### Custom Prompts

Edit `src/strings/strings.rkt` to customize:

- **System prompts** for each mode (`SYSTEM-PROMPT-AGENT`, `SYSTEM-PROMPT-ARCHITECT`, `SYSTEM-PROMPT-ASK`)
- **Security messages** (`MSG-SECURITY-ALERT`, `MSG-SECURITY-DENIED`)
- **LLM Judge prompt** (`PROMPT-LLM-JUDGE`)
- **Help text** (`HELP-TEXT-INTERACTIVE`, `HELP-TEXT-CLIENT`)
- **Error messages** (`ERR-NO-API-KEY`, `ERR-CONNECTION-FAILED`)

### Budget and Timeout Control

**Set Session Limits:**
```bash
# $5 budget limit
agentd --budget 5.00 "Complete this refactoring task"

# 30 minute timeout
agentd --timeout 1800 "Analyze and fix all linting issues"

# Combined
agentd --budget 2.00 --timeout 600 "Quick task with limits"
```

**Monitoring Costs:**

In interactive mode:
```
/cost
```

At session end, a summary is displayed:
```
───────────────────────────── Session Summary ─────────────────────────────
Duration        5m 23s
Turns           12

Model Usage:
  gpt-5.2          8 calls   15,234 in · 3,456 out   $0.0234

Tokens          15,234 input   3,456 output   18,690 total
Cost            $0.0234

Tools Used:
  read_file            12 calls   (45 lifetime)
  write_file           3 calls    (12 lifetime)
  grep_code            5 calls    (28 lifetime)
──────────────────────────────────────────────────────────────────────────
```

### MCP Server Integration

Connect external MCP (Model Context Protocol) servers to add new tools dynamically:

```
Add an MCP server named "filesystem" using npx with args ["@anthropic/mcp-filesystem"]
```

This uses the `add_mcp_server` tool to:
1. Start the MCP subprocess
2. Register all tools from the server
3. Make them available to the agent

### Session Management

**List Sessions:**
```
/session list
```

**Create New Session:**
```
/session new my-project
```

**Switch Session:**
```
/session switch my-project
```

**Delete Session:**
```
/session delete old-session
```

Sessions persist to `~/.agentd/context.json` and include:
- System prompt (possibly evolved)
- Mode and priority settings
- Conversation history
- Compacted summary for long conversations

---

## 10. Troubleshooting

### Common Errors

**"No API key configured"**
```
Error: [ERROR] No API key configured. Set OPENAI_API_KEY in your environment.
```
Solution: Set the `OPENAI_API_KEY` environment variable or add it to `.env`.

**"Permission Denied: Requires Level X"**
```
Permission Denied: Requires security level 2.
```
Solution: Increase security level with `--perms 2` or higher.

**"jj executable not found"**
```
jj (Jujutsu) executable not found. Install from https://martinvonz.github.io/jj/
```
Solution: Install Jujutsu VCS or use Git tools instead.

**"Resource Limit Exceeded"**
```
Resource Limit Exceeded: Execution stopped.
```
Solution: Increase `--budget` or `--timeout`, or reduce task scope.

### Debug Levels

| Level | Output |
|-------|--------|
| `0` | Silent (errors only) |
| `1` | Info (tool calls, costs) |
| `2` / `verbose` | Verbose (full traces) |

**Enable Debug Mode:**
```bash
agentd --debug 1 "Your task"
agentd --debug verbose "Detailed tracing"
```

Debug output includes:
- Tool invocations and arguments
- API call costs and token counts
- Sandbox execution details
- Optimizer steps

### Log Locations

| File | Purpose |
|------|---------|
| `~/.agentd/context.json` | Session contexts and history |
| `~/.agentd/evals.jsonl` | Task evaluation logs |
| `~/.agentd/profile_stats.json` | Aggregate profile statistics |
| `~/.agentd/traces.jsonl` | Execution traces |
| `~/.agentd/meta_prompt.txt` | Evolved optimizer prompt |
| `~/.agentd/workspace/` | Sandboxed file workspace |

### Getting Help

**Interactive Help:**
```
/help
```

**Documentation:**
- README.md — Overview and quick start
- scribblings/chrysalis-forge.scrbl — Scribble documentation
- doc/USAGE.md — This guide

**Community:**
- GitHub Issues: Report bugs and request features
- Pull Requests: Contribute improvements

---

## Quick Reference

### Essential Commands

```bash
# Start interactive session
agentd -i

# Run single task
agentd "Your task"

# With permissions and priority
agentd --perms 2 --priority fast "Task"

# Start service
agentd --serve --serve-port 8080

# Connect client
chrysalis-client --url http://localhost:8080

# ACP for IDE
agentd --acp
```

### Interactive Slash Commands

| Command | Description |
|---------|-------------|
| `/help` | Show help |
| `/mode <mode>` | Switch mode |
| `/model <name>` | Switch model |
| `/session <cmd>` | Session management |
| `/config` | View/set configuration |
| `/cost` | Show session cost |
| `/stats` | Show profile statistics |
| `/evolve <feedback>` | Trigger evolution |
| `/init` | Initialize agents.md |
| `/exit` | Exit session |

### Security Quick Reference

| Need | Command |
|------|---------|
| Read-only analysis | `--perms 0` or `--perms 1` |
| Create/modify files | `--perms 2` |
| Run shell commands | `--perms 3` |
| Fully automated | `--perms god` |

### Priority Quick Reference

| Need | Flag |
|------|------|
| Speed | `--priority fast` |
| Low cost | `--priority cheap` |
| Accuracy | `--priority best` |
| Detailed output | `--priority verbose` |
| Natural language | `--priority "your description"` |
