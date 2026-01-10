# LLM Integration

This directory handles all interactions with Large Language Models and provides the DSPy-style programming model.

## Modules

- **`dspy-core.rkt`**: Core DSL for Signatures, Modules (Predict, CoT), and the execution runtime.
- **`dspy-compile.rkt`**: Utilities for optimizing and compiling DSPy modules.
- **`openai-client.rkt`**: Low-level client for OpenAI-compatible APIs, including token estimation and image generation.
- **`openai-responses-stream.rkt`**: Handles streaming responses and real-time tool calls.
- **`pricing-model.rkt`**: Real-time cost estimation and retrieval of model pricing.
