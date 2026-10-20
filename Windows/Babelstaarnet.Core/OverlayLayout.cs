namespace Babelstaarnet.Core;

public readonly record struct PixelSize(int Width, int Height);
public sealed record LearningBubbleFrames(PixelRect Word, PixelRect Sentence);

// A direct port of OverlayLayout.learningBubbleCenters on macOS, with
// Windows' downward Y axis. Both panels avoid the complete source block.
public static class OverlayLayout
{
    public const double WordWidth = 280;
    public const double SentenceWidth = 420;
    public const int Gap = 9;
    public static PixelRect Union(PixelRect a, PixelRect b) => new(Math.Min(a.X, b.X), Math.Min(a.Y, b.Y),
        Math.Max(a.Right, b.Right) - Math.Min(a.X, b.X), Math.Max(a.Bottom, b.Bottom) - Math.Min(a.Y, b.Y));
    public static bool Intersects(PixelRect a, PixelRect b) => a.X < b.Right && a.Right > b.X && a.Y < b.Bottom && a.Bottom > b.Y;
    private static PixelRect Inflate(PixelRect r, int amount) => new(r.X - amount, r.Y - amount, r.Width + amount * 2, r.Height + amount * 2);
    private static bool Contains(PixelRect a, PixelRect b) => b.X >= a.X && b.Y >= a.Y && b.Right <= a.Right && b.Bottom <= a.Bottom;
    public static PixelRect SourceFrame(HoveredText hit) => hit.SourceBounds ?? Union(hit.Line.Frame, hit.Word.Bounds);
    public static PixelRect FocusRule(PixelRect word) => new(word.X - 1, word.Bottom + 2, word.Width + 2, 2);

    public static LearningBubbleFrames? Place(PixelRect word, PixelRect source, PixelSize wordSize,
        PixelSize sentenceSize, PixelRect screen, double scale = 1)
    {
        int gap = (int)Math.Ceiling(Gap * scale);
        int inset = (int)Math.Ceiling(8 * scale);
        int clearance = (int)Math.Ceiling(3 * scale);
        PixelRect? Safe(PixelRect candidate, params PixelRect[] obstacles)
        {
            var inner = Inflate(screen, -inset);
            if (candidate.Width > inner.Width || candidate.Height > inner.Height) return null;
            var clamped = candidate with { X = Math.Clamp(candidate.X, inner.X, inner.Right - candidate.Width),
                Y = Math.Clamp(candidate.Y, inner.Y, inner.Bottom - candidate.Height) };
            return Contains(inner, clamped) && !obstacles.Any(o => Intersects(clamped, Inflate(o, clearance))) ? clamped : null;
        }
        double Distance(PixelRect candidate)
        {
            int dx = Math.Max(Math.Max(word.X - candidate.Right, candidate.X - word.Right), 0);
            int dy = Math.Max(Math.Max(word.Y - candidate.Bottom, candidate.Y - word.Bottom), 0);
            return Math.Sqrt((double)dx * dx + (double)dy * dy);
        }
        int centerX = word.X + word.Width / 2;
        int centerY = word.Y + word.Height / 2;
        var wordCandidates = Around(word, wordSize, gap).Concat(new[]
        {
            new PixelRect(source.Right + gap, centerY - wordSize.Height / 2, wordSize.Width, wordSize.Height),
            new PixelRect(source.X - gap - wordSize.Width, centerY - wordSize.Height / 2, wordSize.Width, wordSize.Height),
            new PixelRect(centerX - wordSize.Width / 2, source.Y - gap - wordSize.Height, wordSize.Width, wordSize.Height),
            new PixelRect(centerX - wordSize.Width / 2, source.Bottom + gap, wordSize.Width, wordSize.Height),
            new PixelRect(centerX - wordSize.Width / 2, source.Y - gap * 2 - sentenceSize.Height - wordSize.Height, wordSize.Width, wordSize.Height)
        }).Select((r, i) => (r, i)).OrderBy(p => Math.Round(Distance(p.r) * 2) / 2).ThenBy(p => p.i);
        var sentenceCandidates = new[]
        {
            new PixelRect(centerX - sentenceSize.Width / 2, source.Bottom + gap, sentenceSize.Width, sentenceSize.Height),
            new PixelRect(centerX - sentenceSize.Width / 2, source.Y - gap - sentenceSize.Height, sentenceSize.Width, sentenceSize.Height)
        }.Concat(Around(source, sentenceSize, gap, belowFirst: true)).ToArray();
        foreach (var candidate in wordCandidates)
        {
            if (Safe(candidate.r, source) is not { } wordFrame) continue;
            foreach (var next in sentenceCandidates.Concat(Around(Union(source, wordFrame), sentenceSize, gap, belowFirst: true)))
                if (Safe(next, source, wordFrame) is { } sentenceFrame && wordFrame.Bottom + gap / 2 <= sentenceFrame.Y)
                    return new(wordFrame, sentenceFrame);
        }
        return null;
    }

    public static PixelRect? PlaceWord(PixelRect word, PixelRect source, PixelSize size, PixelRect screen, double scale = 1)
    {
        // A tall source block can leave room for only one panel. Keep the
        // answer visible while still refusing to print over the source text.
        var pair = Place(word, source, size, new(0, 0), screen, scale);
        return pair?.Word;
    }

    public static PixelRect? PlaceSingle(PixelRect word, PixelRect source, PixelSize size, PixelRect screen, bool sentence, double scale = 1)
    {
        int gap = (int)Math.Ceiling(Gap * scale), inset = (int)Math.Ceiling(8 * scale);
        var inner = Inflate(screen, -inset);
        if (size.Width > inner.Width || size.Height > inner.Height) return null;
        foreach (var candidate in Around(source, size, gap, sentence).Concat(Around(word, size, gap, sentence)))
        {
            var frame = candidate with { X = Math.Clamp(candidate.X, inner.X, inner.Right - size.Width), Y = Math.Clamp(candidate.Y, inner.Y, inner.Bottom - size.Height) };
            if (!Intersects(frame, Inflate(source, (int)Math.Ceiling(3 * scale)))) return frame;
        }
        return null;
    }

    private static IEnumerable<PixelRect> Around(PixelRect anchor, PixelSize size, int gap, bool belowFirst = false)
    {
        var above = new PixelRect(anchor.X + (anchor.Width - size.Width) / 2, anchor.Y - gap - size.Height, size.Width, size.Height);
        var below = new PixelRect(anchor.X + (anchor.Width - size.Width) / 2, anchor.Bottom + gap, size.Width, size.Height);
        var right = new PixelRect(anchor.Right + gap, anchor.Y + (anchor.Height - size.Height) / 2, size.Width, size.Height);
        var left = new PixelRect(anchor.X - gap - size.Width, anchor.Y + (anchor.Height - size.Height) / 2, size.Width, size.Height);
        return belowFirst ? [below, above, right, left] : [above, right, left, below];
    }
}
