namespace Babelstaarnet.Core;

public static class AdaptiveCapture
{
    public static PixelRect Plan(PixelPoint pointer, PixelRect screen, double? textHeight = null, double scale = 1, double velocityX = 0, double velocityY = 0, double expansion = 1)
    {
        double height = Math.Clamp((textHeight ?? 22 * scale) / scale, 8, 96);
        double speed = Math.Sqrt(velocityX * velocityX + velocityY * velocityY) / scale;
        double growth = Math.Min(1 + speed / 2800, 1.32);
        int width = Math.Min(screen.Width, (int)Math.Ceiling(Math.Clamp(Math.Max(960, height * 24), 960, 1420) * growth * expansion * scale));
        int h = Math.Min(screen.Height, (int)Math.Ceiling(Math.Clamp(Math.Max(250, height * 7.5), 250, 820) * Math.Min(growth, 1.18) * expansion * scale));
        double lookAhead = Math.Min(width * .18, speed * scale * .12), magnitude = Math.Max(1, speed * scale);
        return new(Math.Clamp((int)Math.Round(pointer.X + velocityX / magnitude * lookAhead - width / 2.0), screen.X, screen.Right - width),
            Math.Clamp((int)Math.Round(pointer.Y + velocityY / magnitude * lookAhead - h / 2.0), screen.Y, screen.Bottom - h), width, h);
    }
    public static bool NeedsExpansion(IReadOnlyList<RecognizedLine> lines, PixelRect frame, PixelPoint? focus = null)
    {
        if (focus is { } point && ReadingPolicy.HitTest(lines, point) is { } hit && hit.Line.Words.Count > 0)
        {
            int edge = Math.Max(48, hit.Line.Words.Select(w => w.Bounds.Height).Order().ElementAt(hit.Line.Words.Count / 2));
            bool leftCut = hit.Line.Frame.X <= frame.X + edge;
            bool rightCut = hit.Line.Frame.Right >= frame.Right - edge && !SentenceBoundary.EndsSentence(hit.Line.Text);
            if (leftCut || rightCut) return true;
        }
        var words = lines.SelectMany(l => l.Words).Take(3).ToArray();
        if (words.Length >= 3) return false;
        if (words.Length == 0) return true;
        int margin = Math.Max(12, words.Select(w => w.Bounds.Height).Order().ElementAt(words.Length / 2));
        return words.Any(w => w.Bounds.X <= frame.X + margin || w.Bounds.Right >= frame.Right - margin || w.Bounds.Y <= frame.Y + margin || w.Bounds.Bottom >= frame.Bottom - margin);
    }
}
