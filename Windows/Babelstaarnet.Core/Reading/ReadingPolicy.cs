using System.Text.RegularExpressions;

namespace Babelstaarnet.Core;

public readonly record struct PixelPoint(int X, int Y);

public readonly record struct PixelRect(int X, int Y, int Width, int Height)
{
    public int Right => X + Width;
    public int Bottom => Y + Height;
    public bool Contains(PixelPoint point, int tolerance = 0) =>
        point.X >= X - tolerance && point.X < Right + tolerance &&
        point.Y >= Y - tolerance && point.Y < Bottom + tolerance;

    public static PixelRect CaptureAround(PixelPoint point, PixelRect screen)
    {
        int width = Math.Min(1200, screen.Width);
        int height = Math.Min(360, screen.Height);
        return new(Math.Clamp(point.X - width / 2, screen.X, screen.Right - width),
            Math.Clamp(point.Y - height / 2, screen.Y, screen.Bottom - height), width, height);
    }

    public static PixelPoint PlaceBubble(PixelRect word, int width, int height, PixelRect workArea)
    {
        int x = Math.Clamp(word.X, workArea.X, Math.Max(workArea.X, workArea.Right - width));
        int y = word.Y - height - 12;
        if (y < workArea.Y) y = word.Bottom + 12;
        return new(x, Math.Clamp(y, workArea.Y, Math.Max(workArea.Y, workArea.Bottom - height)));
    }
}

public sealed record RecognizedWord(string Text, PixelRect Bounds);
public sealed record RecognizedLine(string Text, IReadOnlyList<RecognizedWord> Words)
{
    public PixelRect Frame { get; } = Words.Count == 0 ? default : Words.Select(w => w.Bounds).Aggregate(OverlayLayout.Union);
}
public sealed record HoveredText(RecognizedWord Word, RecognizedLine Line, int FocusOccurrence = 0, PixelRect? SourceBounds = null);
public sealed record TextUnit(string Value, int Index, int Length);

public static partial class ReadingPolicy
{
    // The Windows composition root supplies the OS dictionary segmenter. Core
    // fixtures have a Unicode-scalar fallback and never depend on WinRT.
    public static Func<string, IReadOnlyList<TextUnit>>? CjkTokenizer { get; set; }
    public static bool HasCjk(string text) => text.Any(c => c is >= '\u3400' and <= '\u9fff' or >= '\uf900' and <= '\ufaff');
    public static IReadOnlyList<TextUnit> Units(string text)
    {
        if (HasCjk(text) && CjkTokenizer is { } tokenize) return tokenize(text);
        return Words().Matches(text).Select(m => new TextUnit(m.Value, m.Index, m.Length)).ToArray();
    }
    // Learning identity preserves Danish spelling, exactly as the Mac profile.
    public static string Key(string text) => EdgePunctuation().Replace(text.Normalize().Trim().ToLowerInvariant(), "");
    public static string FoldKey(string text) => Key(text).Replace("æ", "ae").Replace("ø", "oe").Replace("å", "aa");
    public static bool TryGloss(IReadOnlyDictionary<string, string> glosses, string word, out string meaning) =>
        glosses.TryGetValue(Key(word), out meaning!) || glosses.TryGetValue(FoldKey(word), out meaning!);

    [GeneratedRegex(@"^[^\p{L}\p{M}]+|[^\p{L}\p{M}]+$")]
    private static partial Regex EdgePunctuation();

    [GeneratedRegex(@"(?=[\p{L}\p{M}\p{N}]*\p{L})[\p{L}\p{M}\p{N}]+(?:['’\-][\p{L}\p{M}\p{N}]+)*")]
    public static partial Regex Words();

    public static HoveredText? HitTest(IEnumerable<RecognizedLine> lines, PixelPoint point)
    {
        // An expanded box must never beat an actual hit on the adjacent word.
        foreach (int tolerance in new[] { 0, 3 })
            foreach (var line in lines)
                foreach (var word in line.Words)
                    if (word.Bounds.Contains(point, tolerance) && Words().IsMatch(word.Text))
                        return new(word, line);
        return null;
    }

    // This is an in-place reading aid, not a reordered sentence translation.
    public static string Bridge(string sentence, IReadOnlyDictionary<string, string> glosses,
        Func<string, bool> leaveInDanish)
    {
        var result = new System.Text.StringBuilder(); int previous = 0;
        foreach (var unit in Units(sentence))
        {
            result.Append(sentence.AsSpan(previous, unit.Index - previous)); string key = Key(unit.Value);
            result.Append(leaveInDanish(key) || !TryGloss(glosses, key, out var gloss) || string.IsNullOrWhiteSpace(gloss) ? unit.Value : gloss);
            previous = unit.Index + unit.Length;
        }
        result.Append(sentence.AsSpan(previous)); return result.ToString();
    }

    public static readonly HashSet<string> StructuralWords = new(DanishLanguage.Shared.StructuralWords.Select(Key));
    public static readonly IReadOnlyDictionary<string, string> Glosses = DanishLanguage.Shared.Glosses;
}
