# Agent Guidance: Testing

Always verify your changes by running the relevant tests.

## Running Tests
- Run all tests: `racket tests/run-tests.rkt`
- Run a specific test: `raco test tests/test-xxx.rkt`

## Writing Tests
- Follow the pattern in `test-utils-time.rkt` for simple logic.
- Use `rackunit` for assertions.
- For tool tests, use the mocked environment found in `test-acp-tools.rkt`.

## Test Generation
- You can use the `generate_tests` tool to help bootstrap tests for new modules.
