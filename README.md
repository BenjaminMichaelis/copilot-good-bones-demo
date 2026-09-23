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
