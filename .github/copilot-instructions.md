# SessionBoard house rules

.NET 10 / C# 14 minimal API. Write it the way we'd approve it today, not the way
Stack Overflow answers wrote it in 2015.

## Serialization
- Use `System.Text.Json` only. Never add or use `Newtonsoft.Json` / `JsonConvert` —
  it's an extra dependency `System.Text.Json` already replaces, and minimal APIs
  serialize through it by default.

## Data shapes
- Model DTOs as `record` (or `record struct` for small value-like data), not
  mutable classes. Records give us value equality and immutability for free, and
  they signal "this is data, not a service."

## Time
- Never call `DateTime.Now` / `DateTime.UtcNow` directly in application code.
  Inject `TimeProvider` (constructor or parameter) and call
  `timeProvider.GetUtcNow()`. Direct clock reads make code untestable and hide
  time-zone bugs.

## Async
- Async all the way: no `.Result` or `.Wait()` on a `Task`/`Task<T>`. Blocking on
  async code risks deadlocks and wastes threads; await it instead.

## Style
- File-scoped namespaces (`namespace Foo;`), not block-scoped.
- Nullable reference types are enabled — respect warnings, don't suppress them.
- Use primary constructors where they remove boilerplate (services, DTOs).
- Minimal API endpoints return `TypedResults` (e.g. `TypedResults.Ok(...)`), not
  the non-generic `Results` helper, so response types show up in OpenAPI/tests.

## Build & test
```powershell
dotnet build
dotnet test
```

## When unsure
- Not sure about a .NET 10 / C# 14 API or behavior? Check Microsoft Learn via the
  `microsoft-learn` MCP server instead of guessing from older training data.
- Investigating a runtime error or slow request? Start the app with
  `aspire start --isolated`, then use the `aspire` MCP server (or `aspire describe`
  / `aspire otel logs`) to read real resource health, structured logs, and traces
  instead of guessing from source code alone.

## Lessons
- Before changing code in an area, read `.copilot/lessons/index.md` and any lesson
  it lists for that area. Those are root causes and gotchas this repo already hit.
- Record a new lesson only when asked, following
  `.github/instructions/lessons.instructions.md`.
