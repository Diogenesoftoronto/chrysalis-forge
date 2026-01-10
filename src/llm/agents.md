# Agent Guidance: LLM & DSPy

This directory contains the "brain" of the agent. Use the high-level DSPy abstractions whenever possible.

## Programming Model

1. **Signatures**: Define your task interface first.
   - `(signature MyTask (in [query string?]) (out [answer string?]))`

2. **Modules**: Use `ChainOfThought` for complex reasoning.
   - `(ChainOfThought MySig #:instructions "Be concise")`

3. **Execution**: Use `run-module` to execute a module. It handles prompt rendering and response parsing.

## Cost Management
- Use `calculate-cost` from `pricing-model.rkt` to monitor spend.
- The system automatically polls for real-time pricing updates to keep estimates accurate.

## Model Parameters
- Controls like `model-param` and `vision-model-param` in `main.rkt` determine which LLM is used.
