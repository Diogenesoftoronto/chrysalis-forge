# Core Logic

This directory contains the central engines that drive Chrysalis Forge's intelligence and task execution.

## Modules

- **`acp-stdio.rkt`**: Implements the Agent Command Protocol (ACP) over standard input/output for integration with IDEs.
- **`optimizer-gepa.rkt`**: Implementation of General Evolvable Prompting Architecture for self-optimizing instructions.
- **`optimizer-meta.rkt`**: Higher-level optimization that evolves the optimizers themselves.
- **`process-supervisor.rkt`**: Manages background services and long-running processes.
- **`sub-agent.rkt`**: Parallel task execution engine with specialized capability profiles.
- **`workflow-engine.rkt`**: Orchestrates complex, multi-step tasks and persistent workflows.
