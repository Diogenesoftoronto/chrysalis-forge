# Agent Guidance: Utilities

Use these utilities to keep the codebase clean and observe best practices.

## Debugging
- Use `log-debug` with appropriate levels (0-2) instead of `printf`.
- `(log-debug 1 'category "Message")`

## Error Handling
- Use the retry logic in `utils-retry.rkt` for flaky operations (like LLM calls or network requests).

## Testing
- When asked to generate tests, refer to `test-gen.rkt` for the underlying logic used by the `generate_tests` tool.
