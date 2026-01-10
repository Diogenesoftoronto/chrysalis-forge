# Chrysalis Forge

An evolvable, safety-gated Racket agent framework with DSPy-style optimization.

## Overview

Chrysalis Forge is a Racket-based environment for building and optimizing autonomous agents. It combines modern LLM integration with the safety and expressiveness of the Racket ecosystem.

### Key Features

- **Evolvable Context**: Self-optimizing system prompts based on feedback loop (GEPA).
- **DSPy-style DSL**: Signatures, Modules (Predict, ChainOfThought), and Optimizers for structured LLM interaction.
- **Tiered Sandboxing**: Four levels of security isolation for code execution.
- **Agent Intelligence**: Integrated vector memory, RDF knowledge graphs, and tool-use capabilities.
- **Multi-Transport**: Support for both strict JSON (structured reasoning) and streaming responses (interactive loops).
- **Process Supervision**: Management of background services and long-running capabilities.

## Installation

Ensure you have Racket v9.0+ installed.

```bash
# Clone the repository
git clone https://github.com/diogenes/chrysalis-forge.git
cd chrysalis-forge

# Install dependencies (requires /usr/local/racket/bin/raco or your local equivalent)
/usr/local/racket/bin/raco pkg install --auto
```

## Usage

### Quick Start

Set up your `.env` file with your `OPENAI_API_KEY`.

```bash
cp .env.example .env
# Edit .env with your key
```

### Interactive Mode

Enter a conversational REPL loop by running without arguments:

```bash
racket main.rkt
# or explicitly
racket main.rkt -i
```

### CLI Tasks

Run a single task efficiently:

```bash
racket main.rkt --level-1 "How can I optimize this Racket code?"
```

### Configuration & Local Models

Chrysalis Forge supports custom models and API endpoints (e.g., for **LiteLLM**, **Ollama**, or **LM Studio**).

#### Command Line Flags

- `--model <name>`: Override the default model.
- `--base-url <url>`: Override the API Base URL.
- `--budget <usd>`: Set a strict session budget (e.g., `0.50`). Limits cost.
- `--timeout <duration>`: Set a strict session time limit (e.g., `30s`, `5m`, `1h`).

#### LiteLLM Example

1. Install & Run LiteLLM:
   ```bash
   pip install litellm
   litellm --model ollama/llama3
   ```
2. Connect Chrysalis Forge:
   ```bash
   racket main.rkt --base-url "http://0.0.0.0:4000" --model "ollama/llama3" -i
   ```

Run with Agent Capability Protocol (ACP):

```bash
racket main.rkt --acp
```

## Security Levels

Chrysalis Forge implements a tiered security model:

- **Level 0**: Standard Sandbox (Limited Workspace access).
- **Level 1**: Network Read/Full Filesystem Read.
- **Level 2**: Filesystem Write (Requires user confirmation).
- **Level 3 (God Mode)**: Full Shell Access (Requires user confirmation for destructive commands).

## License

GPL-3.0
