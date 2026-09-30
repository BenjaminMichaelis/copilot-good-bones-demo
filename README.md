# SessionBoard

SessionBoard is a small ASP.NET Core API for conference sessions, speakers, speaker notes, and attendee ratings. It keeps sample data in memory; changes reset when the app restarts.

## Run

```powershell
dotnet run --project src/SessionBoard.Api
```

Available endpoints:

- `GET /sessions` and `GET /sessions/{id}` — list or view sessions
- `GET /sessions/export` — export the session list as JSON
- `DELETE /sessions/{id}` — remove a session
- `GET /speakers` and `GET /speakers/notes?speaker=Speaker%20A` — speaker directory and notes
- `GET /sessions/{id}/ratings` — list a session's ratings
- `POST /sessions/{id}/ratings` — add a rating with a JSON body such as `{"score":5,"comment":"Helpful session"}`

## Test

```powershell
dotnet test
```

## Follow along

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/BenjaminMichaelis/copilot-good-bones-demo)

The Codespace comes with the .NET 10 SDK, GitHub Copilot CLI, the Aspire CLI,
and `jq` (the Linux hook scripts use it). You need a GitHub Copilot plan.

Each talk layer is a git tag. Run the same request against each one and watch
the diff change:

```
Add an endpoint GET /sessions/{id}/summary that returns the session with its average rating and the time until it starts, as JSON.
```

| Tag | What it adds |
|---|---|
| `L0-bare` | Nothing: the app with zero Copilot configuration |
| `L1-instructions` | `.github/copilot-instructions.md`, `AGENTS.md`, a path-scoped test rule |
| `L2-skills` | The `add-endpoint` skill and a VS Code prompt file |
| `L3-agent` | `security-auditor` (read-only), `orchestrator`, and `implementer` agents |
| `L4-mcp` | Microsoft Learn and Aspire MCP servers, a scoped auditor tool, `.copilot/lessons/` |
| `L5-hooks` | Hooks: deny Newtonsoft, deny secrets, build after edits, tests before the agent may stop |
| `L6-plugin` | All of it packaged as an Agent Plugin |

```bash
git checkout L0-bare
copilot                      # /login if prompted, then paste the request above
# discard the agent's changes, then move up a layer:
git checkout -- . && git clean -fd && git checkout L1-instructions
```

Try the other beats too:

- `L3-agent`: `copilot --agent security-auditor -p "Audit this repository for security issues"`,
  or pick the `orchestrator` agent and give it the request above.
- `L4-mcp`: `aspire start --isolated --apphost SessionBoard.AppHost`, call
  `GET /sessions/2/ratings/average` (it returns 500 on purpose), and ask Copilot to
  find out why from the running app, then to record what it learned as a lesson.
- `L5-hooks`: ask Copilot to add `Newtonsoft.Json`, or to put a storage account key
  in `appsettings.json`, and watch the hooks deny it. Hooks and workspace MCP servers
  only run in a folder you've trusted; the CLI asks the first time.

The deeper, hands-on version of every layer is the
[day-in-the-life Copilot lab](https://github.com/ms-mfg-community/day-in-the-life-copilot-lab)
(ContosoUniversity, .NET track): Lab 02 instructions, Lab 04 skills and prompts,
Lab 03 and the hardening lab for agents, Lab 07 orchestration, Lab 05 MCP, Lab 10
memory, Lab 06 hooks, Lab 11 plugins.

## Good bones come from

This repo's build-level conventions (`.editorconfig`, `Directory.Build.props`,
`Directory.Packages.props`, and the strict-format check wired into
`scripts/hooks/verify-build.ps1`/`.sh`) are adopted from the speaker's own
OSS template pack:
[BenjaminMichaelis/DotnetTemplates](https://github.com/BenjaminMichaelis/DotnetTemplates)
(NuGet: `BenjaminMichaelis.Dotnet.Templates`).

```powershell
dotnet new install BenjaminMichaelis.Dotnet.Templates
dotnet new bmichaelis.quickstart.consoleapp
```

The seeded "dated" patterns in this repo (Newtonsoft.Json, `DateTime.Now`,
mutable DTO classes, `.Result`, a string-concatenated filter, an
unauthenticated `DELETE`) are intentional and left in place for the talk —
adopting these conventions catches *new* dated code without silently
"fixing" the examples the talk depends on.
