# Agent Guidance: Core Logic

The `core` directory is where the agent's high-level strategy and execution flow reside.

## Evolution & Optimization
- **GEPA**: Use `gepa-evolve!` to improve system prompts based on runtime feedback.
- **Meta-GEPA**: This is for evolving the *logic* of the optimization itself.

## Task Management
- Use `sub-agent.rkt` to delegate work. 
- All sub-agents must have a `profile` which restricts their tool access (e.g., `editor`, `researcher`).

## Workflow
- `workflow-engine.rkt` is for multi-turn processes that need to survive restarts or span many independent steps.
