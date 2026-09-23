// Template for a new DTO used by an endpoint. Copy and adjust — do not use a
// mutable class with { get; set; } for new DTOs.

namespace SessionBoard.Api;

/// <summary>Example response DTO — replace with real fields.</summary>
public record ExampleResponseDto(int Id, string Title);

// If the endpoint needs "now" (dates, durations, expiry), inject TimeProvider
// rather than reading DateTime.Now/DateTime.UtcNow directly:
//
//   static Results<Ok<ExampleResponseDto>, NotFound> GetExample(
//       int id, SessionStore store, TimeProvider timeProvider)
//   {
//       if (store.FindSession(id) is not { } session)
//       {
//           return TypedResults.NotFound();
//       }
//
//       var now = timeProvider.GetUtcNow();
//       return TypedResults.Ok(new ExampleResponseDto(session.Id, session.Title));
//   }
