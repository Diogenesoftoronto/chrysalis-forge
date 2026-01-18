# Agent Architecture in Chrysalis Forge

Chrysalis Forge defines agents as **Evolvable Modules** that combine logic, state, optimization, and self-improvement.

## Core Components

### 1. Signatures (`src/llm/dspy-core.rkt`)
Signatures define the interface of an agent's task — input fields and expected output fields.
```racket
(define OptSig (signature Opt (in [inst string?] [fails string?]) (out [thought string?] [new_inst string?])))
```

### 2. Modules (`src/llm/dspy-core.rkt`)
- **Predict**: Direct completion based on a signature
- **ChainOfThought (CoT)**: Structured reasoning before output
- **Demos**: Few-shot examples to guide performance

### 3. Context & Persistence (`src/stores/context-store.rkt`)
Agents operate within a `Ctx` (Context):
- `system`: High-level persona and rules
- `memory`: Working memory/scratchpad
- `tool-hints`: Guidance on tool usage
- `mode`: Operational mode gating tool access:
  - **`ask`**: Basic interaction, no filesystem
  - **`architect`**: Read files for analysis
  - **`code`**: Full capabilities including write, network, services
  - **`semantic`**: RDF Knowledge Graph mode

**Project Rules**: `.chrysalis/rules.md` in the working directory is automatically appended to the system prompt.

### 4. Tool System (`src/tools/acp-tools.rkt`)

**28+ Tools** organized by category:

| Category | Tools |
|----------|-------|
| **File** | read_file, write_file, patch_file, preview_diff, open_in_editor, file_rollback, file_rollback_list, list_dir, grep_code |
| **Git** | git_status, git_diff, git_log, git_commit, git_checkout |
| **Jujutsu** | jj_status, jj_log, jj_diff, jj_undo, jj_op_log, jj_op_restore, jj_workspace_add, jj_workspace_list, jj_describe, jj_new |
| **Evolution** | suggest_profile, profile_stats, evolve_system, log_feedback, use_llm_judge |
| **MCP** | add_mcp_server (dynamically adds external tool servers) |

### 5. Sub-Agents (`src/core/sub-agent.rkt`)

Parallel task execution with specialized tool profiles:

```racket
(spawn-sub-agent! "Refactor this file" run-fn #:profile 'editor)
```

**Profiles**:
- `editor`: File creation/modification tools
- `researcher`: Read-only search tools
- `vcs`: Git + Jujutsu tools
- `all`: Full toolkit

Tools: `spawn_task`, `await_task`, `task_status`

### 6. Test Generation (`src/utils/test-gen.rkt`)

LLM-powered, language-agnostic test generation:
```racket
(test-gen-execute args api-key send-fn)
```

## Optimization & Evolution

### GEPA (General Evolvable Prompting Architecture)
`optimizer-gepa.rkt` — Evolves system prompts based on feedback:
```racket
(gepa-evolve! "The agent should be more concise")
```

### Meta-Optimization
`optimizer-meta.rkt` + `dspy-compile.rkt` — Evolves the optimizer itself:
1. Bootstrap few-shot examples
2. Instruction mutation testing

### Eval Store (`src/stores/eval-store.rkt`)
Tracks sub-agent performance for learning:
- `log-eval!`: Record task results
- `get-profile-stats`: View success rates per profile
- `suggest-profile`: Recommend optimal profile for task type
- `evolve-profile!`: Analyze and improve profiles

**Feedback Loop**:
```
log_feedback → eval-store → profile_stats → suggest_profile
                          ↓
              evolve_system → GEPA → improved prompts
```

## Execution Loop (Modular Entry Layer)

The entry layer is split into focused modules:

| Module | Purpose |
|--------|---------|
| `main.rkt` | CLI parsing, mode dispatch, `acp-run-turn` conversation loop (~470 lines) |
| `src/core/runtime.rkt` | Shared parameters (`model-param`, session counters) and helpers |
| `src/core/commands.rkt` | Slash command handlers and session management |
| `src/core/repl.rkt` | REPL loop, terminal handling, multiline input |

**Core Loop**:
1. **Prompt Rendering**: Module + context + inputs compiled to prompt
2. **Tool Execution**: Security-gated via `execute-acp-tool`
3. **Auto-Correction**: `run-code-with-retry!` retries failed executions
4. **Context Compaction**: Automatic summarization when approaching token limits
5. **Trace Logging**: All tasks logged to `traces.jsonl`
6. **Eval Logging**: Profile performance logged to `evals.jsonl`

## Process Supervision (`src/core/process-supervisor.rkt`)

Manage long-running services:
- `spawn-service!`: Start background process
- `stop-service!`: Terminate service
- `list-services!`: View active services

## Thread System (`src/core/thread-manager.rkt`, `src/stores/thread-store.rkt`)

Threads provide user-facing conversation continuity while hiding session implementation details.

### Hierarchy
```
Project → Thread → Context Nodes
                 ↓ (hidden)
              Sessions
```

### Thread Relations
- `continues_from`: Linear continuation of a thread
- `child_of`: Hierarchical breakdown into subtopics
- `relates_to`: Loose association

### CLI Commands
```
/thread list           - List all threads
/thread new <title>    - Create new thread
/thread switch <id>    - Switch to a thread
/thread continue       - Create continuation thread
/thread child <title>  - Create child thread
/thread info           - Show current thread details
/thread context add    - Add hierarchical context node
```

### HTTP API
- `GET/POST /v1/threads` - List/create threads
- `GET/PATCH /v1/threads/:id` - Get/update thread
- `POST /v1/threads/:id/messages` - Chat on thread
- `POST /v1/threads/:id/relations` - Link threads
- `GET/POST /v1/threads/:id/contexts` - Context nodes
- `GET/POST /v1/projects` - Project management

### Key Functions
```racket
(ensure-thread user-id #:title "My task")     ; Get or create thread
(thread-continue user-id from-id)              ; Create continuation
(thread-spawn-child user-id parent-id title)   ; Create child thread
(get-or-create-session user-id thread-id)      ; Hidden session management
(auto-rotate-if-needed! user-id thread-id)     ; Auto session rotation
```
