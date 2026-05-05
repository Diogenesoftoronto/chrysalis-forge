---
name: terminal-first
description: Keep Chrysalis focused on the terminal workflow before any GUI work.
---

# Terminal First

Use this skill when the task risks drifting into GUI or service work before the shell experience is solid.

Rules:

- default to the shell experience, launcher behavior, prompts, skills, and extension commands
- prefer deterministic local artifacts under `.chrysalis/outputs/`
- keep changes inspectable and easy to run from the command line
- defer browser or GUI work unless the user explicitly asks for it
