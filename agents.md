# Agent Architecture in Chrysalis Forge

The Chrysalis Forge framework defines agents not as static scripts, but as **Evolvable Modules** that combine logic, state, and optimization.

## Core Components

### 1. Signatures (`dspy-core.rkt`)
Signatures define the interface of an agent's task. They specify the input fields and expected output fields, ensuring structured interaction.
Example:
```racket
(define OptSig (signature Opt (in [inst string?] [fails string?]) (out [thought string?] [new_inst string?])))
```

### 2. Modules (`dspy-core.rkt`)
Modules are the fundamental building blocks of agent behavior.
- **Predict**: Direct completion based on a signature.
- **ChainOfThought (CoT)**: Structured reasoning before the final output.
- **Demos**: Few-shot examples stored within the module to guide performance.

### 3. Context & Persistence (`context-store.rkt`)
Agents operate within a `Ctx` (Context), which defines their environment.
- `system`: The high-level persona and rules.
- `memory`: Working memory or scratchpad.
- `tool-hints`: Guidance on how to use available tools.
- `mode`: The current operational mode, which gates tool access:
  - **`ask`**: Basic interaction, no filesystem access.
  - **`architect`**: Permission to read files for analysis.
  - **`code`**: Full capability including filesystem write, networking, and service management.
  - **`semantic`**: Specialized mode for RDF Knowledge Graph interactions.

### 4. Capabilities (Tools)
Agents have access to specialized toolsets depending on their operating mode:
- **`rdf-tools.rkt`**: SPARQL querying and RDF graph management.
- **`vector-store.rkt`**: Semantic search and long-term memory retrieval.
- **`process-supervisor.rkt`**: Spawning and managing external services.
- **`sandbox-exec.rkt`**: Safe execution of Racket code within tiered permission levels.

## Optimization & Evolution

Agents in Chrysalis Forge are designed to improve over time using two primary mechanisms:

### GEPA (General Evolvable Prompting Architecture)
Implemented in `optimizer-gepa.rkt`, this allows the agent's system prompt to evolve based on user feedback. The agent reflects on its failures and updates its own `Ctx-system` prompt.

### Meta-Optimization (`dspy-compile.rkt` & `optimizer-meta.rkt`)
Inspired by DSPy, the compiler can take a module and a training set to:
1.  **Bootstrap Few-shot Examples**: Selecting the best demos for the prompt.
2.  **Instruction Mutation**: Testing multiple versions of instructions to find the one that scores highest against the target task.

## Execution Loop

The entry point in `main.rkt` handles the interaction loop:
1.  **Prompt Rendering**: The module, context, and inputs are compiled into a comprehensive prompt.
2.  **ACP Integration**: Support for the Agent Capability Protocol allows integration with external IDEs and tools.
3.  **Tiered Execution**: All code-related tasks are funneled through the `sandbox-exec.rkt` to ensure security boundaries are respected.
