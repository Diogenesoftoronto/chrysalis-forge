# Agent Guidance: Source Root

The Chrysalis Forge source follows a strict modular structure.

- **Infrastructure**: Found in `stores/` and `utils/`.
- **Intelligence**: Found in `llm/` and `core/`.
- **Capability**: Found in `tools/`.

When modifying the system:
1. **Maintain Decoupling**: Don't leak low-level `net/url` calls into the `core/`. Use the abstractions in `llm/` or `tools/`.
2. **Respect Parameters**: Use Racket parameters for configuration (like `model-param`).
3. **Log Everything**: Use the `debug.rkt` system consistently.
