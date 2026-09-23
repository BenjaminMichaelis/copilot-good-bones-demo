---
description: Flag dated .NET patterns in the current file without editing it
agent: agent
---
<!--
  Prompt files are an older customization mechanism (predates Agent Skills).
  They work in IDE chat only (VS Code, Visual Studio, and JetBrains; public
  preview). In VS Code, invoke this one explicitly as `/modernize-file` and
  name the file. Copilot CLI and the Copilot app do not load prompt files,
  and VS Code's Agent Host is migrating this use case toward Agent Skills —
  prefer the add-endpoint skill (.github/skills/add-endpoint/SKILL.md) for
  anything that should be auto-discovered or used from the CLI or the app.
  This file is kept as a reference example of the prompt-file format.
  (`agent:` replaced the older `mode:` key, which VS Code now flags as
  deprecated.)
-->

# Modernize file

Look at the currently open file (or the file named in the prompt) and flag, in
a short bullet list, any place it uses:

- `Newtonsoft.Json` / `JsonConvert` instead of `System.Text.Json`
- a mutable class DTO instead of a `record`
- `DateTime.Now` / `DateTime.UtcNow` instead of injected `TimeProvider`
- `.Result` / `.Wait()` instead of `await`
- a block-scoped `namespace { ... }` instead of a file-scoped namespace

Do not edit the file — just list what you found and why it matters, per
`.github/copilot-instructions.md`.
