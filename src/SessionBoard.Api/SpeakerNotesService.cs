using System.Data;

namespace SessionBoard.Api
{
#pragma warning disable CA1001 // seeded dated code — undisposed DataTable field, kept intentionally for the talk
    public class SpeakerNotesService
    {
        private readonly DataTable _notes = new();

        public SpeakerNotesService()
        {
            _notes.Columns.Add("Speaker", typeof(string));
            _notes.Columns.Add("Note", typeof(string));
            _notes.Rows.Add("Speaker A", "Check the opening slides");
            _notes.Rows.Add("Speaker B", "Leave time for questions");
            _notes.Rows.Add("Speaker C", "Bring the sample project");
        }

        public List<string> FindForSpeaker(string speaker)
        {
            var filter = "Speaker = '" + speaker + "'";
            return _notes.Select(filter).Select(row => (string)row["Note"]).ToList();
        }
    }
#pragma warning restore CA1001
}
