namespace SessionBoard.Api
{
    public class SessionDto
    {
        public int Id { get; set; }
        public string Title { get; set; } = "";
        public string Speaker { get; set; } = "";
        public string Room { get; set; } = "";
        public DateTime StartsAt { get; set; }
    }

    public class SpeakerDto
    {
        public int Id { get; set; }
        public string Name { get; set; } = "";
    }

    public class RatingDto
    {
        public int SessionId { get; set; }
        public int Score { get; set; }
        public string Comment { get; set; } = "";
    }

    public class NewRatingDto
    {
        public int Score { get; set; }
        public string Comment { get; set; } = "";
    }
}
