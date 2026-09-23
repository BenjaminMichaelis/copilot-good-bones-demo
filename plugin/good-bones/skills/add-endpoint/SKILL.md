---
name: add-endpoint
description: Use when adding a new minimal API endpoint to SessionBoard.Api (a new route, its DTO, and its test). Covers the repo's conventions for records, TypedResults, endpoint registration, and testing.
---

# Add a minimal API endpoint

Follow these steps, in order, when adding a new endpoint to SessionBoard.Api.

1. **Model the data as a record.** If the endpoint needs a request or response
   shape that doesn't already exist, add a `record` (positional or with
   `init` properties) to `src/SessionBoard.Api/Models.cs`. Do not add a
   mutable `class` with `{ get; set; }` — see `template.cs` in this folder for
   the shape to copy.

2. **Write the handler as a local function or lambda** near the other
   endpoints in `Program.cs`, and return `TypedResults` (e.g.
   `TypedResults.Ok(...)`, `TypedResults.NotFound()`), typed as
   `Results<Ok<T>, NotFound>` (or the appropriate union) — not the
   non-generic `Results` helper.

3. **Pull data through `SessionStore`** (or the relevant service). Add a
   method there if the query/mutation doesn't exist yet. If the method needs
   "now", accept `TimeProvider` and call `timeProvider.GetUtcNow()` —
   never `DateTime.Now`.

4. **Register the route** in `Program.cs` with `app.MapGet` / `app.MapPost` /
   etc., next to the other routes for the same resource.

5. **Add a test** in `tests/SessionBoard.Api.Tests/SessionBoardTests.cs`
   (or a new test class for a large new area), following
   `.github/instructions/tests.instructions.md`: `WebApplicationFactory`,
   `Method_Condition_Result` naming, cover the happy path and at least one
   not-found/validation path.

6. **Update `README.md`'s endpoint list** with the new route.

7. **Run `dotnet build` and `dotnet test`** and confirm both are green before
   considering the endpoint done.
