# LLM Integration

This directory handles all interactions with Large Language Models and provides the DSPy-style programming model.

## Modules

- **`dspy-core.rkt`**: Core DSL for Signatures, Modules (Predict, CoT), and the execution runtime. Supports late-binding elite dispatch based on runtime priority.
- **`dspy-compile.rkt`**: Evolutionary optimizer using the **MAP-Elites** algorithm. It transforms base modules into `ModuleArchive` objects containing diverse performance profiles.
- **`openai-client.rkt`**: Low-level client for OpenAI-compatible APIs. Features high-resolution latency tracking and usage metadata for grounded scoring.
- **`openai-responses-stream.rkt`**: Handles streaming responses and real-time tool calls.
- **`pricing-model.rkt`**: Real-time cost estimation and retrieval of model pricing.
- **`harness-evolve.rkt`**: Meta-Harness self-optimization engine. Implements novelty detection (Jaccard n-gram), bandit model ensemble (Thompson Sampling), cross-model generalization testing, harness strategy evolution (12-field struct), and `compile/evolve!` — a drop-in replacement for `compile!` that integrates all four capabilities.
