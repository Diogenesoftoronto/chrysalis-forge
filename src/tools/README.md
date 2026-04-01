# Tools

This directory contains the tool definitions and interfaces for the agent to interact with the external world.

## Modules

- **`acp-tools.rkt`**: The main dispatcher and implementation for standard filesystem, git, jj, self-evolution (GEPA, harness strategy, novelty, bandit), and LLM judge tools.
- **`mcp-client.rkt`**: Client implementation for the Model Context Protocol (MCP), allowing dynamic tool expansion.
- **`rdf-tools.rkt`**: Tools for interacting with the RDF knowledge graph.
- **`sandbox-exec.rkt`**: Logic for tiered sandboxing and safe code execution.
- **`web-search.rkt`**: Web exploration via Exa AI and fallback search methods.
