using System.Net;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Mvc.Testing;
using SessionBoard.Api;

namespace SessionBoard.Api.Tests;

public class SessionBoardTests : IDisposable
{
    private readonly WebApplicationFactory<Program> _factory = new();
    private readonly HttpClient _client;

    public SessionBoardTests()
    {
        _client = _factory.CreateClient();
    }

    [Fact]
    public async Task ListsSeededSessions()
    {
        var sessions = await _client.GetFromJsonAsync<List<SessionDto>>("/sessions");

        Assert.NotNull(sessions);
        Assert.Equal(3, sessions.Count);
        Assert.Contains(sessions, session => session.Title == "Building Reliable APIs");
    }

    [Fact]
    public async Task ExportsSessionsAsJson()
    {
        var response = await _client.GetAsync("/sessions/export");
        var sessions = await response.Content.ReadFromJsonAsync<List<SessionDto>>();

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("application/json", response.Content.Headers.ContentType?.MediaType);
        Assert.Equal(3, sessions?.Count);
    }

    [Fact]
    public async Task ListsSpeakersAndNotes()
    {
        var speakers = await _client.GetFromJsonAsync<List<SpeakerDto>>("/speakers");
        var notes = await _client.GetFromJsonAsync<List<string>>("/speakers/notes?speaker=Speaker%20A");

        Assert.Equal(3, speakers?.Count);
        Assert.Equal("Check the opening slides", Assert.Single(notes!));
    }

    [Fact]
    public async Task AddsAndListsRating()
    {
        var response = await _client.PostAsJsonAsync("/sessions/1/ratings",
            new NewRatingDto { Score = 5, Comment = "Helpful session" });
        var ratings = await _client.GetFromJsonAsync<List<RatingDto>>("/sessions/1/ratings");

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var rating = Assert.Single(ratings!);
        Assert.Equal(1, rating.SessionId);
        Assert.Equal(5, rating.Score);
    }

    [Fact]
    public async Task RejectsOutOfRangeRating()
    {
        var response = await _client.PostAsJsonAsync("/sessions/1/ratings",
            new NewRatingDto { Score = 6, Comment = "Invalid" });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task DeletingSessionRemovesIt()
    {
        var response = await _client.DeleteAsync("/sessions/1");
        var getResponse = await _client.GetAsync("/sessions/1");

        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, getResponse.StatusCode);
    }

    public void Dispose()
    {
        _client.Dispose();
        _factory.Dispose();
    }
}
