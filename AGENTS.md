# AGENTS.md

SessionBoard: a .NET 10 minimal API for tracking conference sessions.

## Layout
- `src/SessionBoard.Api/` — the API (`Program.cs` has endpoint registrations,
  `Models.cs` DTOs, `SessionStore.cs` in-memory data, `SpeakerNotesService.cs`
  speaker lookup).
- `tests/SessionBoard.Api.Tests/` — xUnit integration tests
  (`WebApplicationFactory`-based). See `.github/instructions/tests.instructions.md`.

## Build & test
```powershell
dotnet build
dotnet test
```

House rules for how to write code here live in `.github/copilot-instructions.md`.
