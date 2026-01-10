# Agent Guidance: Tools

Tools are the "hands" of the agent. Most interaction goes through `acp-tools.rkt`.

## Using Tools

1. **Dispatcher**: `execute-acp-tool` is the central entry point for most filesystem and VCS operations.
2. **Security**: Observe the `security-level` parameter. Levels range from 0 (Sandbox) to 4 (God Mode).
3. **MCP**: Use `add_mcp_server` to dynamically attach new toolsets during a session.
4. **Judging**: Many sensitive tools (like `write_file` or `run_term`) are gated by an **LLM Security Judge** if enabled.

## Adding New Tools

- Define the tool metadata (OpenAI Function format) in `make-acp-tools`.
- Implement the handler in `execute-acp-tool`.
- Update the relevant profile in `src/core/sub-agent.rkt` if necessary.
