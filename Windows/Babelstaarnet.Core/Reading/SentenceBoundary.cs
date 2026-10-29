namespace Babelstaarnet.Core;

// Port of BabelCore/SentenceBoundary.swift: Danish periods also mark dates,
// ordinals, abbreviations, initials, decimals and URLs.
public static class SentenceBoundary
{
    private static readonly HashSet<string> Abbreviations = new(DanishLanguage.Shared.Abbreviations.Concat(new[] { "mr", "mrs", "dr", "prof", "etc", "e.g", "i.e" }));
    private const string Stops = ".!?…。！？", Closers = "\"'”’»)]}」』》）】", Openers = "\"'“‘«([{–—-「『《（【";
    public static IReadOnlyList<int> StopLocations(string text)
    {
        var stops = new List<int>();
        for (int i = 0; i < text.Length; i++)
            if (StopEnd(text, i) is { } end) { stops.Add(end); i = end - 1; }
        return stops;
    }
    public static bool EndsSentence(string text) => StopLocations(text.TrimEnd()).LastOrDefault(-1) == text.TrimEnd().Length;
    public static bool StopsBeforeEnd(string text) => StopLocations(text).Any(end => end < text.Length);
    public static (int Start, int End) Containing(string text, int location)
    {
        int start = 0;
        foreach (int end in StopLocations(text))
        {
            if (location < end) return (start, end);
            start = end; while (start < text.Length && char.IsWhiteSpace(text[start])) start++;
        }
        return (start, text.Length);
    }
    private static int? StopEnd(string text, int index)
    {
        char stop = text[index]; if (!Stops.Contains(stop)) return null;
        int end = index + 1; while (end < text.Length && (Stops.Contains(text[end]) || Closers.Contains(text[end]))) end++;
        if ("。！？".Contains(stop)) return end;
        if (end < text.Length)
        {
            if (!char.IsWhiteSpace(text[end])) return null;
            int next = end; while (next < text.Length && (char.IsWhiteSpace(text[next]) || Openers.Contains(text[next]))) next++;
            if (next < text.Length && (char.IsDigit(text[next]) || char.IsLower(text[next]))) return null;
        }
        if (stop != '.') return end;
        int start = index; while (start > 0 && (char.IsLetterOrDigit(text[start - 1]) || text[start - 1] == '.')) start--;
        string stem = text[start..index].ToLowerInvariant();
        if (stem.Length > 0 && (stem.All(c => char.IsDigit(c) || c == '.') || Abbreviations.Contains(stem) || stem.Length == 1 && char.IsLetter(stem[0]))) return null;
        return end;
    }
}
