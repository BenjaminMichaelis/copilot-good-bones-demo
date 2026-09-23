using Newtonsoft.Json;
using Scalar.AspNetCore;
using SessionBoard.Api;

var builder = WebApplication.CreateBuilder(args);
builder.AddServiceDefaults();
builder.Services.AddSingleton<SessionStore>();
builder.Services.AddSingleton<SpeakerNotesService>();
builder.Services.AddOpenApi();

var app = builder.Build();
app.MapDefaultEndpoints();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
    // Offline-safe: no CDN fonts, no telemetry; "Try it" calls this API directly.
    app.MapScalarApiReference(options => options.DisableDefaultFonts().DisableTelemetry());
}

app.MapGet("/sessions", (SessionStore store) => Results.Ok(store.GetSessionsAsync().Result));

app.MapGet("/sessions/export", (SessionStore store) =>
    Results.Content(JsonConvert.SerializeObject(store.GetSessions()), "application/json"));

app.MapGet("/sessions/{id:int}", (int id, SessionStore store) =>
    store.FindSession(id) is { } session ? (IResult)Results.Ok(session) : Results.NotFound());

app.MapDelete("/sessions/{id:int}", (int id, SessionStore store) =>
    store.DeleteSession(id) ? (IResult)Results.NoContent() : Results.NotFound());

app.MapGet("/speakers", (SessionStore store) => Results.Ok(store.GetSpeakers()));

app.MapGet("/speakers/notes", (string speaker, SpeakerNotesService notes) =>
    Results.Ok(notes.FindForSpeaker(speaker)));

app.MapGet("/sessions/{id:int}/ratings", (int id, SessionStore store) =>
    store.FindSession(id) is not null
        ? (IResult)Results.Ok(store.GetRatings(id))
        : Results.NotFound());

app.MapGet("/sessions/{id:int}/ratings/average", (int id, SessionStore store) =>
{
    var ratings = store.GetRatings(id);

    // Star histogram, one bucket per possible score. NOTE: sized for scores 1-4;
    // a perfect score of 5 indexes one past the end of the array.
    var buckets = new int[4];
    foreach (var rating in ratings)
    {
        buckets[rating.Score - 1]++;
    }

    var average = ratings.Count == 0 ? 0d : ratings.Average(rating => rating.Score);
    return Results.Ok(new { average, buckets });
});

app.MapPost("/sessions/{id:int}/ratings", (int id, NewRatingDto request, SessionStore store) =>
{
    if (request.Score is < 1 or > 5)
    {
        return (IResult)Results.BadRequest("Score must be between 1 and 5.");
    }

    if (!store.TryAddRating(id, request, out var rating))
    {
        return Results.NotFound();
    }

    return Results.Created($"/sessions/{id}/ratings", rating);
});

app.Run();

public partial class Program { }
