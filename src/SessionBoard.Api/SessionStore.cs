namespace SessionBoard.Api
{
    public class SessionStore
    {
        private readonly object _sync = new();
        private readonly List<SessionDto> _sessions = new List<SessionDto>
        {
            new SessionDto { Id = 1, Title = "Opening the Conference", Speaker = "Speaker A", Room = "Main Hall", StartsAt = DateTime.Now.AddHours(1) },
            new SessionDto { Id = 2, Title = "Building Reliable APIs", Speaker = "Speaker B", Room = "Room 1", StartsAt = DateTime.Now.AddHours(2) },
            new SessionDto { Id = 3, Title = "Testing in Practice", Speaker = "Speaker C", Room = "Room 2", StartsAt = DateTime.Now.AddHours(3) }
        };
        private readonly List<SpeakerDto> _speakers = new List<SpeakerDto>
        {
            new SpeakerDto { Id = 1, Name = "Speaker A" },
            new SpeakerDto { Id = 2, Name = "Speaker B" },
            new SpeakerDto { Id = 3, Name = "Speaker C" }
        };
        private readonly List<RatingDto> _ratings = new List<RatingDto>
        {
            new RatingDto { SessionId = 2, Score = 5, Comment = "Clear examples" }
        };

        public List<SessionDto> GetSessions()
        {
            lock (_sync)
            {
                return _sessions.ToList();
            }
        }

        public Task<List<SessionDto>> GetSessionsAsync()
        {
            return Task.FromResult(GetSessions());
        }

        public SessionDto? FindSession(int id)
        {
            lock (_sync)
            {
                return _sessions.FirstOrDefault(session => session.Id == id);
            }
        }

        public bool DeleteSession(int id)
        {
            lock (_sync)
            {
                var session = _sessions.FirstOrDefault(item => item.Id == id);
                if (session is null)
                {
                    return false;
                }

                _ratings.RemoveAll(rating => rating.SessionId == id);
                return _sessions.Remove(session);
            }
        }

        public List<SpeakerDto> GetSpeakers()
        {
            return _speakers.ToList();
        }

        public List<RatingDto> GetRatings(int sessionId)
        {
            lock (_sync)
            {
                return _ratings.Where(rating => rating.SessionId == sessionId).ToList();
            }
        }

        public bool TryAddRating(int sessionId, NewRatingDto request, out RatingDto? rating)
        {
            lock (_sync)
            {
                if (_sessions.All(session => session.Id != sessionId))
                {
                    rating = null;
                    return false;
                }

                rating = new RatingDto
                {
                    SessionId = sessionId,
                    Score = request.Score,
                    Comment = request.Comment
                };
                _ratings.Add(rating);
                return true;
            }
        }
    }
}
