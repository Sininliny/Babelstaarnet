namespace Babelstaarnet.Core;

// The Mac sentence bridge uses a clause-bounded window around the pointed
// occurrence. Keep that occurrence when the same word appears earlier.
public static class SentenceWindow
{
    public static HoveredText Around(HoveredText hit, int limit = 36)
    {
        string text = hit.Line.Text;
        var words = ReadingPolicy.Words().Matches(text);
        var focuses = Enumerable.Range(0, words.Count).Where(i => ReadingPolicy.Key(words[i].Value) == ReadingPolicy.Key(hit.Word.Text)).ToArray();
        if (focuses.Length == 0 || words.Count <= limit) return hit;
        int focus = focuses[Math.Clamp(hit.FocusOccurrence, 0, focuses.Length - 1)];
        int first = Math.Clamp(focus - limit / 2, 0, words.Count - limit);
        int start = words[first].Index, end = words[first + limit - 1].Index + words[first + limit - 1].Length;
        const string separators = ",;:—–()[]";
        for (int i = words[focus].Index - 1; i >= start; i--)
            if (separators.Contains(text[i])) { start = i + 1; break; }
        for (int i = end - 1; i >= words[focus].Index + words[focus].Length; i--)
            if (separators.Contains(text[i])) { end = i; break; }
        string selected = text[start..end].Trim().TrimEnd(',', ';', ':', '-');
        if (selected.Length > 0 && !".!?…".Contains(selected[^1])) selected += ".";
        int occurrence = words.Count(m => m.Index >= start && m.Index < words[focus].Index && ReadingPolicy.Key(m.Value) == ReadingPolicy.Key(hit.Word.Text));
        return hit with { Line = new(selected, hit.Line.Words), FocusOccurrence = occurrence };
    }
}
