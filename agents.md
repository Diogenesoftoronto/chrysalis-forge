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

**Project Rules**: `.agentd/rules.md` in the working directory is automatically appended to the system prompt.

### 4. Tool System (`src/tools/acp-tools.rkt`)

**25 Tools** organized by category:

| Category | Tools |
|----------|-------|
| **File** | read_file, write_file, patch_file, preview_diff, list_dir, grep_code |
| **Git** | git_status, git_diff, git_log, git_commit, git_checkout |
| **Jujutsu** | jj_status, jj_log, jj_diff, jj_undo, jj_op_log, jj_op_restore, jj_workspace_add, jj_workspace_list, jj_describe, jj_new |
| **Evolution** | suggest_profile, profile_stats, evolve_system, log_feedback |

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

## Execution Loop (`main.rkt`)

1. **Prompt Rendering**: Module + context + inputs compiled to prompt
2. **Tool Execution**: Security-gated via `execute-acp-tool`
3. **Auto-Correction**: `run-code-with-retry!` retries failed executions
4. **Trace Logging**: All tasks logged to `traces.jsonl`
5. **Eval Logging**: Profile performance logged to `evals.jsonl`

## Process Supervision (`src/core/process-supervisor.rkt`)

Manage long-running services:
- `spawn-service!`: Start background process
- `stop-service!`: Terminate service
- `list-services!`: View active services
