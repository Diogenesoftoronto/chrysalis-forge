# Using Chrysalis Forge

This guide walks through the practical aspects of using Chrysalis Forge—from installation through advanced features. It's written for developers who want to get things done, with enough depth to understand what's happening under the hood.

---

## Getting Started

### Installation

Chrysalis Forge requires Racket version 9.0 or later. If you don't have Racket installed, grab it from [racket-lang.org](https://racket-lang.org/). You'll also want git for cloning the repository, and curl comes in handy as a fallback for web search when the Exa API isn't available.

Clone and install with:

```bash
git clone https://github.com/diogenesoft/chrysalis-forge.git
cd chrysalis-forge
raco pkg install --auto
```

This registers two commands: `agentd` (the full agent) and `chrysalis-client` (a lightweight client for connecting to remote agent services). The installation process pulls in all Racket dependencies automatically.

### Configuration

Before running the agent, you need to configure at least one thing: your OpenAI API key. Create a `.env` file in the project root:

```bash
OPENAI_API_KEY=sk-...
```

That's the minimum. For richer functionality, you can add:

```bash
# Custom LLM endpoint (for LiteLLM, Ollama, or other OpenAI-compatible APIs)
OPENAI_API_BASE=http://localhost:1234/v1

# Model name (if different from default)
MODEL=gpt-4o

# Exa API for neural web search (falls back to DuckDuckGo via curl otherwise)
EXA_API_KEY=your_exa_key

# For running in service mode with authentication
CHRYSALIS_SECRET_KEY=your-secret-key-here
```

The `.env.example` file in the repository documents all available options.

You can also configure settings interactively using the `/config` command:

```
[USER]> /config list
Current Configuration:
  Model: gpt-5.2
  Base URL: https://api.openai.com/v1
  ...

[USER]> /config model gpt-4o
Model set to gpt-4o

[USER]> /models
Available Models:
  - gpt-4o
  - gpt-4o-mini
  - gpt-4-turbo
  ...
```

Use `/config list` to see all current settings, and `/models` to discover available models from your API endpoint.

---

## Running the Agent

### Interactive Mode

The most common way to use Chrysalis Forge is interactive mode, which drops you into a REPL where you can have a conversation with the agent:

```bash
agentd -i
```

Once inside, you can type natural language requests. The agent reads your input, reasons about it, calls tools as needed, and responds. A typical session might look like:

```
[USER]> What files are in this project?
[AGENT uses list_dir, displays results]

[USER]> Show me how the optimizer works
[AGENT uses read_file on src/core/optimizer-gepa.rkt, explains the code]

[USER]> I think it should log more information. Can you add debug output?
[AGENT uses patch_file to add logging, shows diff, asks for confirmation]
```

The agent's tool usage is transparent. You see which tools it invokes and what results come back. This transparency is intentional—you should never wonder what the agent did on your behalf.

Several commands are available within the REPL (all start with `/`):

- `/help` - Show available commands
- `/exit`, `/quit` - Exit the session
- `/config list` - List current configuration (model, API key status, etc.)
- `/config <key> <value>` - Set configuration values (model, budget, priority, etc.)
- `/models` - List available models from your API endpoint
- `/workflows` - List available workflows
- `/workflows show <slug>` - Show details of a specific workflow
- `/workflows delete <slug>` - Delete a workflow
- `/mode code` switches to full-capability mode, enabling file writes and shell commands
- `/mode architect` enables read-only file access for code analysis
- `/priority fast` switches to speed-optimized operation
- `/evolve "The agent should be more concise"` triggers GEPA prompt evolution
- `/stats` shows profile performance statistics
- `/session list` - List all sessions
- `/session new <name>` - Create a new session
- `/session switch <name>` - Switch to a different session
- `/raco <args>` - Run raco commands
- `/init` - Initialize project and generate agents.md

### Single-Task Mode

For scripting or quick tasks, pass the prompt directly on the command line:

```bash
agentd "Explain what this codebase does"
```

The agent runs, produces output, and exits. This is useful for automation or when you just need a quick answer. Combine with flags to control behavior:

```bash
# Allow file modifications (security level 2)
agentd --perms 2 "Fix the type error in parser.rkt"

# Use a specific model with speed priority
agentd --model gpt-5.2 --priority fast "Summarize the README"

# Set a budget cap
agentd --budget 0.50 "Deep analysis of the codebase architecture"
```

### Service Mode

For multi-user deployments or remote access, run Chrysalis Forge as an HTTP service:

```bash
agentd --serve --serve-port 8080
```

This exposes an OpenAI-compatible API at `/v1/chat/completions`, meaning existing tools that speak the OpenAI protocol can connect directly. The service also provides endpoints for user management (`/auth/register`, `/auth/login`) and session tracking (`/v1/sessions`).

Connect with the included client:

```bash
chrysalis-client --url http://localhost:8080 --api-key your-jwt-token
```

### IDE Integration

For integration with editors like Amp Code or Zed, use ACP mode:

```bash
agentd --acp
```

This starts a JSON-RPC server on stdio, enabling bidirectional communication with the IDE. The editor can send prompts, and the agent can request file reads, display diffs, and interact with the IDE's UI.

---

## Understanding Modes and Security

Chrysalis Forge implements a layered security model. Two orthogonal concepts control what the agent can do: **modes** and **security levels**.

### Modes

A mode determines which category of tools the agent can access. Think of modes as role-based access control:

**ask** is the most restricted mode. The agent can only converse and use basic utilities. No filesystem access, no network calls. This is the safe mode for experimentation.

**architect** adds read-only file access. The agent can read files, list directories, and search code, but cannot modify anything. This is appropriate for code review and analysis tasks.

**code** unlocks full capabilities: file writes, shell commands, network access, everything. This is the power mode for actual development work.

**semantic** enables RDF knowledge graph operations for semantic memory and reasoning.

Switch modes with the `/mode` command or by starting the agent with a specific mode configured.

### Security Levels

Security levels add another dimension of control, governing *how* dangerous operations are handled:

**Level 0** is pure sandbox—no execution of anything that could affect the system.

**Level 1** allows safe operations: reading files, running sandboxed Racket expressions, basic network reads.

**Level 2** permits file writes, but requires confirmation. Every write operation prompts you before executing.

**Level 3** enables shell access, again with confirmation for each command.

**god** mode (yes, that's what it's called) auto-approves everything. Use this only in controlled environments where you trust the agent completely.

Set the security level with `--perms`:

```bash
agentd --perms 2 "Refactor the parser module"
```

For additional safety, you can enable an LLM-based security judge that reviews operations before execution:

```bash
export LLM_JUDGE=true
agentd --perms 3 "Run the test suite"
```

The judge receives the proposed operation and responds with [SAFE] or [UNSAFE]. It's not foolproof, but it catches obvious problems.

---

## The Tool System

Chrysalis Forge provides 25 built-in tools organized into categories. Understanding these tools helps you understand what the agent can do.

### File Operations

The core file tools are `read_file`, `write_file`, `patch_file`, `list_dir`, and `grep_code`. The agent uses these automatically when you ask it to examine or modify code.

What's notable is `patch_file`—rather than rewriting entire files, the agent can make surgical edits to specific line ranges. This produces cleaner diffs and reduces the risk of unintended changes. When the agent decides to patch, it shows you the diff before applying:

```
[AGENT proposes patch to src/parser.rkt, lines 45-52]
--- a/src/parser.rkt
+++ b/src/parser.rkt
@@ -45,8 +45,10 @@
   (define tokens (tokenize input))
+  (log-debug "Tokenized: ~a tokens" (length tokens))
   (parse-tokens tokens))

Apply this change? [y/N]
```

### Version Control

Two version control systems are supported: git and Jujutsu (jj).

The git tools (`git_status`, `git_diff`, `git_log`, `git_commit`, `git_checkout`) provide standard repository operations. Nothing surprising here.

The Jujutsu tools are more interesting. Jujutsu is a next-generation VCS that treats history as mutable. The killer feature is `jj_undo`—instant rollback of any operation, including commits. If the agent makes a mistake, `jj_undo` reverts it immediately. The operation log (`jj_op_log`) shows what happened, and `jj_op_restore` can restore any previous state.

For agents making changes to code, this safety net is invaluable. Mistakes become cheap because they're trivially reversible.

### Web Search

When the agent needs external information, it uses `web_search`, `web_fetch`, or `web_search_news`. If you've configured the Exa API key, searches use neural search for semantic matching. Otherwise, they fall back to DuckDuckGo via curl.

The agent decides when to search. If you ask about a library it doesn't know about, or request recent news, it will search automatically.

### Sub-Agents

Perhaps the most powerful tools are the sub-agent tools: `spawn_task`, `await_task`, and `task_status`.

Sub-agents are parallel workers that handle subtasks independently. Each sub-agent runs in its own thread with a focused tool profile. When you ask the agent to do something complex—like researching multiple files, making coordinated changes, or gathering information from several sources—it can spawn sub-agents to work in parallel.

Profiles restrict what each sub-agent can do:

- **editor** sub-agents can read and write files but can't search the web
- **researcher** sub-agents can read and search but can't modify anything  
- **vcs** sub-agents handle version control operations
- **all** gives full access (used sparingly)

This profile system serves two purposes: it focuses each sub-agent on its task (reducing confusion and errors), and it provides a security boundary (a researcher can't accidentally overwrite files).

### Self-Evolution

The evolution tools (`evolve_system`, `log_feedback`, `suggest_profile`, `profile_stats`) let you interact with the learning system.

`evolve_system` triggers GEPA optimization. You provide feedback ("The agent should be more concise" or "It keeps missing edge cases in tests"), and the system evolves the prompt to address that feedback.

`log_feedback` records task outcomes for learning. When a task succeeds or fails, logging it helps the system learn which approaches work.

`suggest_profile` queries the accumulated learning data to recommend which sub-agent profile suits a given task type.

`profile_stats` shows raw performance data—success rates, average durations, costs per profile.

---

## Priority Selection

One of the distinctive features of Chrysalis Forge is priority-aware execution. Rather than always using the "best" model configuration, you can specify what you're optimizing for.

### Keywords

The simplest approach uses keywords:

```bash
agentd --priority fast "Quick status check"
agentd --priority cheap "Batch analysis"
agentd --priority accurate "Critical code review"
```

Each keyword maps to a target in phenotype space. "Fast" prioritizes low latency, accepting potentially lower accuracy. "Cheap" minimizes token cost. "Accurate" (or "best") prioritizes correctness regardless of time or cost.

### Natural Language

For more nuanced preferences, use natural language:

```bash
agentd --priority "I need accuracy but I'm on a budget" "Review this security code"
agentd --priority "Balance speed and quality" "Generate tests"
```

The system interprets this description and finds the module variant in its archive that best matches your stated preferences. Under the hood, it uses KNN search in a normalized phenotype space.

### Autonomous Priority Switching

The agent can change its own priority mid-task using the `set_priority` tool. If it encounters a subtask that's taking too long, it might switch to "fast" mode. If it hits something critical, it might upgrade to "best". This autonomous adaptation makes the agent more effective across varied workloads.

---

## Project-Specific Configuration

### Rules Files

Every project is different. Chrysalis Forge supports project-specific configuration through `.agentd/rules.md` files. Place this file in your project root, and its contents are automatically appended to the agent's system prompt.

A typical rules file might contain:

```markdown
# Project Rules

## Code Style
We use TypeScript with strict mode. Prefer functional components in React.
All exports should be typed explicitly.

## Testing
Use Jest with React Testing Library. Test files live in __tests__ directories
adjacent to the code they test. Mock external services.

## Git Conventions
Use conventional commits: feat:, fix:, docs:, refactor:, test:, chore:
Keep commits atomic. Squash before merging.

## Project Structure
- src/components/ — React components
- src/hooks/ — Custom hooks
- src/services/ — API and external service clients
- src/utils/ — Pure utility functions
```

The agent incorporates these rules into its behavior. When you ask it to create a component, it follows your style guide. When it commits, it uses your commit message format.

### Agents.md Files

The repository also recognizes `agents.md` (or `AGENTS.md`) files placed in directories. These provide localized guidance for specific parts of the codebase. For example, `src/llm/agents.md` might contain instructions specific to the LLM layer.

---

## Self-Evolution in Practice

Chrysalis Forge isn't static—it learns from use. Understanding how to leverage this makes the agent more valuable over time.

### Triggering Evolution

When you notice the agent consistently making certain mistakes or missing certain patterns, provide feedback:

```
/evolve "The agent generates code that's too verbose. It should prefer concise, idiomatic expressions."
```

This triggers GEPA optimization. The system examines its current prompt alongside your feedback, reflects on what's going wrong, and generates an improved prompt. The evolved prompt is stored and used for future interactions.

You can also evolve through the tool:

```
Use evolve_system to make the agent better at generating TypeScript types
```

### Viewing Learning Data

The `/stats` command shows profile performance:

```
/stats
```

Output might show:

```
Profile: editor
  Success rate: 87%
  Average duration: 4.2s
  Average cost: $0.003
  
Profile: researcher  
  Success rate: 94%
  Average duration: 6.8s
  Average cost: $0.005
```

This data reveals which configurations work well and which need improvement.

### The Learning Loop

Every task execution contributes to learning:

1. Task is assigned to a profile
2. Execution proceeds, results logged to eval store
3. Profile statistics are updated
4. Future profile suggestions incorporate this data
5. Periodic evolution incorporates accumulated feedback

Over time, the agent adapts to your specific use patterns.

---

## Advanced Usage

### Parallel Sub-Agents

For complex tasks, explicitly request parallel execution:

```
Spawn three sub-agents:
1. A researcher to analyze src/parser.rkt
2. A researcher to analyze src/lexer.rkt  
3. An editor to prepare a refactoring plan

Wait for all to complete, then synthesize their findings.
```

The agent spawns the sub-agents, monitors their progress, and collects results. This can dramatically speed up tasks that decompose naturally into independent parts.

### Custom LLM Endpoints

Chrysalis Forge works with any OpenAI-compatible API. For local models:

```bash
# With Ollama
agentd --base-url http://localhost:11434/v1 --model llama3.2 -i

# With LiteLLM
OPENAI_API_BASE=http://localhost:4000/v1 agentd -i

# With vLLM
agentd --base-url http://localhost:8000/v1 --model mistral-7b-instruct -i
```

### Budget and Timeout Control

For production use, set limits:

```bash
# Stop after spending $2
agentd --budget 2.00 "Deep codebase analysis"

# Stop after 10 minutes
agentd --timeout 10m "Comprehensive test generation"
```

The agent respects these limits, wrapping up gracefully when approaching them.

---

## Troubleshooting

### Common Issues

**"API key not found"** — Ensure `OPENAI_API_KEY` is set in your environment or `.env` file. Use `/config list` to check your configuration, or run with `-d verbose` to see environment variable status.

**"Unknown Model" or "Model not found"** — The default model may not be valid for your API endpoint. Use `/models` to list available models, then set one with `/config model <name>`.

**"Permission denied"** — You're trying an operation that requires a higher security level. Use `--perms 2` or `--perms 3`.

**"Tool not available in this mode"** — Switch to a mode that includes the tool. Use `/mode code` for full access.

**Slow responses** — Try `--priority fast` or a faster model. Check if network issues are causing API delays.

**API errors (400, 404, etc.)** — The system now shows helpful error messages instead of crashing. Check:
- Your API endpoint is correct (`/config list` shows your base URL)
- The model name is valid for your endpoint (`/models` lists available models)
- Your API key is valid (use `-d verbose` to verify)

### Debug Output

Increase debug verbosity to see what's happening:

```bash
chrysalis -d verbose
# or
chrysalis --debug verbose
```

Debug levels:
- 0: Minimal output (default)
- 1: Show tool calls and major events
- 2: Detailed logging including API calls
- verbose: Everything, including environment variable checks and raw payloads

When using verbose debug mode (`-d verbose`), the system automatically checks all environment variables and displays:
- ✓ Set variables with their values (API keys are partially masked)
- ○ Optional variables that are not set (using defaults)
- Critical errors for missing required variables (like `OPENAI_API_KEY`)

This helps diagnose configuration issues quickly.

### Log Locations

Persistent logs live in `~/.agentd/`:

- `traces.jsonl` — Full operation traces
- `evals.jsonl` — Task outcome evaluations  
- `context.json` — Stored contexts and sessions
- `meta_prompt.txt` — The current meta-optimizer prompt

Examining these files can reveal what the agent has been doing and how its behavior has evolved.
