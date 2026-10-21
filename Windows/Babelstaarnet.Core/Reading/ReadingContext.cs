using System.Text;

namespace Babelstaarnet.Core;

public static class ReadingContext
{
    public static HoveredText Assemble(HoveredText hit, IReadOnlyList<RecognizedLine> lines)
    {
        if (hit.Line.Words.Count == 0) return hit;
        string anchorText = DanishLanguage.Compact(hit.Line.Text);
        string focusKey = ReadingPolicy.Key(hit.Word.Text);
        int wordIndex = hit.Line.Words.ToList().FindIndex(w => w == hit.Word);
        int occurrence = hit.Line.Words.Take(Math.Max(0, wordIndex)).Count(w => ReadingPolicy.Key(w.Text) == focusKey);
        var matches = ReadingPolicy.Words().Matches(anchorText).Where(m => ReadingPolicy.Key(m.Value) == focusKey).ToArray();
        int focusOffset = matches.Length == 0 ? 0 : matches[Math.Min(occurrence, matches.Length - 1)].Index;
        int focusEnd = focusOffset + (matches.Length == 0 ? hit.Word.Text.Length : matches[Math.Min(occurrence, matches.Length - 1)].Length);
        var stops = SentenceBoundary.StopLocations(anchorText);
        var selected = new List<RecognizedLine> { hit.Line };
        var used = new HashSet<RecognizedLine> { hit.Line };
        RecognizedLine? Neighbor(RecognizedLine line, bool above) => lines
            .Where(l => l.Words.Count > 0 && !used.Contains(l) && (above ? l.Frame.Y < line.Frame.Y : l.Frame.Y > line.Frame.Y) && Continues(above ? l : line, above ? line : l))
            .MinBy(l => Math.Abs(l.Frame.Y - line.Frame.Y));
        if (!stops.Any(s => s <= focusOffset))
            for (int added = 0; added < 3 && Neighbor(selected[0], true) is { } prior; added++)
            {
                used.Add(prior); string text = DanishLanguage.Compact(prior.Text);
                if (SentenceBoundary.EndsSentence(text)) break;
                selected.Insert(0, prior); if (SentenceBoundary.StopsBeforeEnd(text)) break;
            }
        if (!stops.Any(s => s >= focusEnd))
            for (int added = 0; added < 3 && !SentenceBoundary.EndsSentence(DanishLanguage.Compact(selected[^1].Text)) && Neighbor(selected[^1], false) is { } next; added++)
            {
                used.Add(next); selected.Add(next); if (SentenceBoundary.StopsBeforeEnd(next.Text)) break;
            }
        var joined = new StringBuilder(); RecognizedWord word = hit.Word; int location = focusOffset;
        for (int i = 0; i < selected.Count; i++)
        {
            var line = selected[i]; string text = DanishLanguage.Compact(line.Text);
            bool joins = i > 0 && joined.Length > 0 && joined[^1] == '-' && text.Length > 0 && char.IsLower(text[0]);
            if (joins)
            {
                joined.Length--;
                string combined = selected[i - 1].Words[^1].Text.TrimEnd('-') + line.Words[0].Text;
                if (word == selected[i - 1].Words[^1] || word == line.Words[0]) word = word with { Text = combined };
            }
            else if (i > 0) joined.Append(' ');
            if (ReferenceEquals(line, hit.Line)) location = joined.Length + focusOffset;
            joined.Append(text);
        }
        string whole = joined.ToString(); var range = SentenceBoundary.Containing(whole, location);
        int start = range.Start; while (start < range.End && char.IsWhiteSpace(whole[start])) start++;
        string sentence = whole[start..range.End].TrimEnd();
        int focusInSentence = Math.Clamp(location - start, 0, sentence.Length);
        int focusOccurrence = ReadingPolicy.Words().Matches(sentence).Count(m => m.Index + m.Length <= focusInSentence && ReadingPolicy.Key(m.Value) == ReadingPolicy.Key(word.Text));
        return new(word, new(sentence, selected.SelectMany(l => l.Words).ToArray()), focusOccurrence, selected.Select(l => l.Frame).Aggregate(OverlayLayout.Union));
    }

    private static bool Continues(RecognizedLine upper, RecognizedLine lower)
    {
        var a = upper.Frame; var b = lower.Frame;
        if (a.Height <= 0 || b.Height <= 0) return false;
        double height = Math.Max(a.Height, b.Height), gap = b.Y - a.Bottom;
        double overlap = Math.Min(a.Right, b.Right) - Math.Max(a.X, b.X);
        double ratio = (double)a.Height / b.Height;
        return gap <= height * 1.25 && gap >= -height * .6 && overlap >= Math.Min(a.Width, b.Width) * .4 && ratio is >= .7 and <= 1.45;
    }
}
