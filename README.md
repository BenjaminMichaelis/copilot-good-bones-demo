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
