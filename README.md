# Chrysalis Forge

An evolvable, safety-gated Racket agent framework with DSPy-style optimization and self-improving capabilities.

## Overview

Chrysalis Forge is a Racket-based environment for building and optimizing autonomous agents. It combines modern LLM integration with the safety and expressiveness of the Racket ecosystem.

### Key Features

- **Evolvable Context**: Self-optimizing system prompts via GEPA (General Evolvable Prompting Architecture)
- **DSPy-style DSL**: Signatures, Modules (Predict, ChainOfThought), and Optimizers
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

### Interactive Mode
```bash
racket main.rkt -i
```

### CLI Tasks
```bash
racket main.rkt --level-1 "Analyze this code"
```

### Configuration
- `--model <name>`: Override model (default: gpt-5.2)
- `--base-url <url>`: Custom API endpoint (LiteLLM, Ollama, etc.)
- `--budget <usd>`: Session budget limit
- `--timeout <duration>`: Session time limit

### Project Rules
Create `.agentd/rules.md` in your project root to add project-specific instructions to the agent's system prompt.

## Security Levels

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

## License

GPL-3.0
