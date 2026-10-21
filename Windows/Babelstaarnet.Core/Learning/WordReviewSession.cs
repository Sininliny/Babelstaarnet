namespace Babelstaarnet.Core;

public sealed class WordReviewSession
{
    private readonly List<VocabularyEntry> queue;
    private readonly HashSet<string> askedAgain = [];
    public int Position { get; private set; }
    public int Count => queue.Count;
    public VocabularyEntry? Current => Position < queue.Count ? queue[Position] : null;
    public bool Revealed { get; set; }
    public int Remembered { get; private set; }
    public int Forgotten { get; private set; }
    public WordReviewSession(IEnumerable<VocabularyEntry> entries) => queue = entries.ToList();
    public void Answer(bool remembered)
    {
        if (Current is not { } entry || !Revealed) return;
        if (remembered) Remembered++; else { Forgotten++; if (askedAgain.Add(entry.Key)) queue.Add(entry); }
        Position++; Revealed = false;
    }
}
