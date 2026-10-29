using Babelstaarnet.Core;
using System;
using System.Collections.Generic;
using System.Linq;
using Windows.Data.Text;

namespace Babelstaarnet.Windows;

internal static class CjkWords
{
    public static IReadOnlyList<TextUnit> Segment(string text)
    {
        // Create per request: the OS segmenter is apartment-bound.
        var tokenizer = new WordsSegmenter("zh");
        return tokenizer.GetTokens(text).Where(t => t.Text.Any(char.IsLetter))
            .Select(t => new TextUnit(t.Text, (int)t.SourceTextSegment.StartPosition, (int)t.SourceTextSegment.Length)).ToArray();
    }
    public static RecognizedLine SegmentLine(RecognizedLine line)
    {
        if (!ReadingPolicy.HasCjk(line.Text)) return line;
        var boxes = new List<(int Start, int End, PixelRect Box)>(); int search = 0;
        foreach (var word in line.Words)
        {
            int start = line.Text.IndexOf(word.Text, search, StringComparison.Ordinal);
            if (start < 0) continue;
            boxes.Add((start, start + word.Text.Length, word.Bounds)); search = start + word.Text.Length;
        }
        var result = new List<RecognizedWord>();
        foreach (var token in Segment(line.Text))
        {
            var pieces = boxes.Where(b => b.Start < token.Index + token.Length && b.End > token.Index).Select(b =>
            {
                double width = (double)b.Box.Width / (b.End - b.Start);
                int left = b.Box.X + (int)Math.Floor(Math.Max(0, token.Index - b.Start) * width);
                int right = b.Box.X + (int)Math.Ceiling(Math.Min(b.End - b.Start, token.Index + token.Length - b.Start) * width);
                return new PixelRect(left, b.Box.Y, Math.Max(1, right - left), b.Box.Height);
            }).ToArray();
            if (pieces.Length > 0) result.Add(new(token.Value, pieces.Aggregate(OverlayLayout.Union)));
        }
        return result.Count == 0 ? line : new(line.Text, result);
    }
}
