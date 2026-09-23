# good-bones plugin

Portable Agent Plugins 1.0 packaging of this repo's `L2`–`L5` configuration
layers (add-endpoint skill, security-auditor agent, and the Newtonsoft deny,
secret-scan, build-verification, and test-gate hooks), so the same house rules
can be installed into *other* repositories without copying `.github/skills`,
`.github/agents`, and `.github/hooks` by hand.

Deliberately **not** bundled:

- MCP servers — project-specific infrastructure; they stay in the repo's
  `.mcp.json` / `.vscode/mcp.json`.
- The `orchestrator` and `implementer` agents — plugin agents are namespaced
  (`good-bones:implementer`), so a bundled orchestrator's hand-offs would need
  plugin-specific names. They stay in the repo's `.github/agents/`.
- `.copilot/lessons/` — a repo's memory belongs to that repo.

This repo's own `.github/` layers remain the source of truth and are what the
`Lx-*` git tags demonstrate layer by layer. This `plugin/good-bones/` folder is
an additional, optional artifact showing how the same three components could
be distributed as a single installable unit via
`copilot plugin install <source>`.

## Layout (Agent Plugins 1.0)

```
plugin.json                                   # manifest ($schema = Agent Plugins 1.0)
skills/add-endpoint/SKILL.md                  # portable skill (discovered by any compatible client)
skills/add-endpoint/template.cs
com.github.copilot/agents/security-auditor.agent.md   # Copilot-CLI-specific (client-namespaced)
com.github.copilot/hooks/hooks.json                    # Copilot-CLI-specific
com.github.copilot/hooks/scripts/*.ps1|*.sh            # hook scripts, referenced via ${PLUGIN_ROOT}
com.github.copilot/hooks/scripts/Invoke-DotNetFormatStrict.ps1  # bundled strict-format check
                                                        # (adopted from BenjaminMichaelis/DotnetTemplates,
                                                        # see the repo root README's "Good bones come from")
```

## Verifying locally (isolated config home only)

```powershell
$env:COPILOT_HOME = "D:\copilot-isolated-home"
copilot plugin install ".\plugin\good-bones"
copilot plugin list
```

Never install this into the real `~/.copilot` — always point `COPILOT_HOME` at
an isolated directory first.
