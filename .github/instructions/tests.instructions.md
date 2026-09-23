---
applyTo: "tests/**"
---

# Test conventions

- Framework: xUnit. Use `[Fact]` / `[Theory]`, `Assert.*` — no other assertion
  library.
- Integration tests spin up the API via `WebApplicationFactory<Program>` (see
  `SessionBoardTests`'s constructor) and hit it through the `HttpClient` it
  provides — don't instantiate `SessionStore`/services directly to bypass the
  HTTP pipeline.
- Name test methods `Method_Condition_Result`, e.g.
  `GetSessionSummary_UnknownId_ReturnsNotFound`. Prefer this over vague names
  like `Test1` or `ItWorks`.
- One behavior per test. If you're asserting two unrelated things, split it.
- New endpoints need at least: the happy path, and the not-found/validation
  path.
- Run `dotnet test` before considering a change done.
