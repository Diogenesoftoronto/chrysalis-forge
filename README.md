# Chrysalis Forge

An evolvable, safety-gated Racket agent framework with DSPy-style optimization and self-improving capabilities.

## Overview

Chrysalis Forge is a Racket-based environment for building and optimizing autonomous agents. It combines modern LLM integration with the safety and expressiveness of the Racket ecosystem.

![Features Overview](.vhs/features-overview.gif)

### Key Features

- **Evolvable Context**: Self-optimizing system prompts via GEPA (General Evolvable Prompting Architecture)
- **DSPy-style DSL**: Signatures, Modules (Predict, ChainOfThought), and Optimizers
- **MAP-Elites Optimization**: Evolutionary optimization targeting cost, latency, and token efficiency
- **Grounded Scoring**: Automated grading based on precision, speed ($/ms), and resource consumption
- **Tiered Sandboxing**: Four levels of security isolation for code execution
- **25 Built-in Tools**: File operations, code search, git, jj (Jujutsu), and self-evolution
- **Parallel Sub-Agents**: Spawn concurrent tasks with specialized tool profiles
- **Auto-Correction Loop**: Retry failed code execution with automatic fixes
- **Vector Memory & RDF**: Semantic search and knowledge graph integration

## Tool Categories

### File & Code Tools
| Tool | Description |
|------|-------------|
| `read_file` | Read file contents |
| `write_file` | Write/create files |
| `patch_file` | Surgical line-range edits |
| `preview_diff` | Preview changes before writing |
| `list_dir` | Directory listing |
| `grep_code` | Regex search across files |

### Git Tools
| Tool | Description |
|------|-------------|
| `git_status` | Repository status |
| `git_diff` | Show changes |
| `git_log` | Commit history |
| `git_commit` | Stage and commit |
| `git_checkout` | Branch operations |

### Jujutsu (jj) Tools — Next-Gen VCS
| Tool | Description |
|------|-------------|
| `jj_status` | Current state |
| `jj_log` | Commit graph |
| `jj_diff` | Show changes |
| `jj_undo` | Undo last operation (instant rollback!) |
| `jj_op_log` | Operation history |
| `jj_op_restore` | Restore to any past state |
| `jj_workspace_add` | Create parallel worktree |
| `jj_workspace_list` | List workspaces |
| `jj_describe` | Set commit message |
| `jj_new` | Create new change |

### Sub-Agent Tools
| Tool | Description |
|------|-------------|
| `spawn_task` | Spawn parallel sub-agent with profile |
| `await_task` | Wait for sub-agent completion |
| `task_status` | Check sub-agent status |

**Profiles**: `editor`, `researcher`, `vcs`, `all`

### Self-Evolution Tools
| Tool | Description |
|------|-------------|
| `suggest_profile` | Get optimal profile for task type |
| `profile_stats` | View learning data |
| `evolve_system` | Trigger GEPA to improve prompts |
| `log_feedback` | Log task results for learning |
| `generate_tests` | LLM-powered test generation |
| `set_priority` | Autonomously switch performance profile (`fast`, `cheap`, etc.) |

### Web Search Tools (`web-search.rkt`)
| Tool | Description |
|------|-------------|
| `web_search` | Exa AI semantic search (falls back to curl/DuckDuckGo) |
| `web_fetch` | Fetch URL content via curl |
| `web_search_news` | Search recent news with date filtering |

**Requires**: `EXA_API_KEY` env var for Exa API, otherwise uses curl fallback.

## Installation

Requires Racket v9.0+.

```bash
git clone https://github.com/diogenes/chrysalis-forge.git
cd chrysalis-forge
/usr/local/racket/bin/raco pkg install --auto
```

## Usage

![Help Command](.vhs/help.gif)

### Interactive Mode
```bash
chrysalis -i
```

![Interactive Demo](.vhs/interactive-demo.gif)

### CLI Tasks
```bash
chrysalis --perms 1 "Analyze this code"
```

### Configuration
- `--model <name>`: Override model (default: gpt-5.2)
- `--base-url <url>`: Custom API endpoint (LiteLLM, Ollama, etc.)
- `--priority <p>`: Set execution profile (`best`, `cheap`, `fast`, `verbose`)
- `--budget <usd>`: Session budget limit
- `--timeout <duration>`: Session time limit

### Project Rules
Create `.chrysalis/rules.md` in your project root to add project-specific instructions to the agent's system prompt.

## Security Levels

![Security Levels](.vhs/security-levels.gif)

- **Level 0**: Sandbox (limited access)
- **Level 1**: Network read + full filesystem read
- **Level 2**: Filesystem write (requires confirmation)
- **Level 3**: Full shell access

## Self-Evolution

The agent learns and improves through:
1. **GEPA**: Evolves system prompts based on feedback
2. **Meta-GEPA**: Evolves the optimizer itself
3. **Profile Learning**: Tracks which tool profiles succeed per task type
4. **Eval Store**: Logs all task results for analysis

## MAP-Elites Optimization
 
 The agent utilizes a specialized **MAP-Elites** evolutionary loop to maintain a library of diverse, high-performing instruction candidates:
 
 - **Behavioral Binning**: Candidates are categorized into "niches" based on Latency, Cost, and Token Usage.
 - **Grounded Scoring**: Optimization is driven by precise telemetry:
   - **Accuracy**: Primary reward for correct output.
   - **Latency Penalty**: Deductions for slow response times.
   - **Cost Penalty**: Deductions based on real-world token pricing.
 - **Dynamic Elite Selection**: At runtime, you or the agent can switch between candidates via the `/config priority` command or the `set_priority` tool.

## Natural Language Priority Selection

One of the most powerful features is the ability to select agent "personalities" using **natural language**:

![Priority Selection](.vhs/priority-selection.gif)

```bash
# Use keyword shortcuts
chrysalis --priority fast "Summarize this file"
chrysalis --priority cheap "Analyze this code"

# Or describe what you need in plain English
chrysalis --priority "I'm broke but need precision" "Review this PR"
chrysalis --priority "I'm in a hurry" "Quick summary"
```

The system uses **K-Nearest Neighbor search** in a geometric phenotype space to find the elite agent that best matches your stated priorities. Keywords like `fast`, `cheap`, `accurate`, and `concise` are mapped directly; other phrases are interpreted by the LLM to find the optimal trade-off.

The agent can also **set its own priority** mid-task using the `set_priority` tool if it determines that a task requires a different speed/cost profile.

## Documentation

Comprehensive documentation is available in the `doc/` directory:

| Document | Description |
|----------|-------------|
| [**THEORY.md**](doc/THEORY.md) | Theoretical foundations — GEPA, MAP-Elites, Grassmann flows, MAKER, Graphiti/Zep, Recursive LMs |
| [**ARCHITECTURE.md**](doc/ARCHITECTURE.md) | System architecture — layers, data flow, DSPy programming model, phenotype spaces |
| [**USAGE.md**](doc/USAGE.md) | Usage guide — installation, CLI, tools, modes, security, self-evolution |
| [**API.md**](doc/API.md) | API reference — data structures, functions, extending the system |
| [**CONFIG.md**](doc/CONFIG.md) | Configuration reference — TOML settings, environment variables |
| [**SERVICE.md**](doc/SERVICE.md) | Service layer — authentication, billing, rate limiting, API router |
| [**RDF-SEMANTIC.md**](doc/RDF-SEMANTIC.md) | Semantic memory — vector store, RDF knowledge graphs |
| [**geometric-decomposition.md**](doc/geometric-decomposition.md) | Deep dive into the geometric decomposition system |

### For Researchers

Start with [THEORY.md](doc/THEORY.md) to understand the research papers that inspired Chrysalis Forge:
- **GEPA** (arXiv:2507.19457) — Reflective prompt evolution outperforming RL
- **MAP-Elites** (arXiv:1504.04909) — Quality-diversity optimization
- **MAKER** (arXiv:2511.09030) — Million-step zero-error reasoning via extreme decomposition
- **Grassmann Flows** (arXiv:2512.19428) — Geometric alternatives to attention
- **Graphiti/Zep** (arXiv:2501.13956) — Temporal knowledge graphs for agent memory
- **Recursive LMs** (arXiv:2512.24601) — Unbounded context via recursive decomposition

### For Developers

Start with [USAGE.md](doc/USAGE.md) for practical usage, then [API.md](doc/API.md) for extension.
 
## License

GPL-3.0

