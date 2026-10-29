using Babelstaarnet.Core;
using Babelstaarnet.Windows;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

internal static class OcrAppearanceChecks
{
    internal sealed record Sample(string Language, string Text, string Focus);
    internal sealed record Appearance(string Id, string Foreground, string Background, string? End = null);
    private sealed record Corpus(Sample[] Samples, Appearance[] Appearances, int[] Sizes);
    internal sealed record Measurement(string Language, string Appearance, string Font, int Size, string Expected, string Recognized,
        double CharacterError, bool FocusHit, double Milliseconds, int Passes);
    internal static async Task<int> RunAsync(string output)
    {
        ReadingPolicy.CjkTokenizer = CjkWords.Segment;
        var corpus = JsonSerializer.Deserialize<Corpus>(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Shared", "ocr-corpus.json")), new JsonSerializerOptions { PropertyNameCaseInsensitive = true })!;
        var results = new List<Measurement>(); var skipped = new List<string>();
        foreach (var sample in corpus.Samples)
        {
            var language = LanguageCatalog.Get(sample.Language);
            if (!new ScreenReader(language: language).IsAvailable) { skipped.Add(sample.Language); continue; }
            await new ScreenReader(language: language).WarmAsync();
            foreach (var appearance in corpus.Appearances)
            foreach (int size in corpus.Sizes)
            foreach (bool serif in new[] { false, true })
            {
                string requested = language.Cjk ? (serif ? "SimSun" : sample.Language == "zh-Hant" ? "Microsoft JhengHei" : "Microsoft YaHei") : serif ? "Times New Roman" : "Segoe UI";
                using var font = new Font(requested, size, serif && !language.Cjk ? FontStyle.Italic : FontStyle.Regular, GraphicsUnit.Pixel);
                using var image = Render(sample, appearance, font, out var focus);
                var reader = new ScreenReader(language: language); var watch = Stopwatch.StartNew();
                var lines = await reader.RecognizeAsync(image, new(-120, 80), CancellationToken.None, focus with { X = focus.X - 120, Y = focus.Y + 80 });
                watch.Stop(); string text = string.Join(' ', lines.Select(l => l.Text));
                bool hit = lines.SelectMany(l => l.Words).Any(w => Normalize(w.Text) == Normalize(sample.Focus) && w.Bounds.Contains(new(focus.X - 120, focus.Y + 80), 4));
                results.Add(new(sample.Language, appearance.Id, font.Name + (font.Italic ? " italic" : ""), size, sample.Text, text, Error(sample.Text, text), hit, watch.Elapsed.TotalMilliseconds, reader.Recognitions));
            }
        }
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(output))!);
        File.WriteAllText(output, JsonSerializer.Serialize(new { skipped, results }, new JsonSerializerOptions { WriteIndented = true }));
        foreach (var group in results.GroupBy(r => r.Language)) Console.WriteLine($"{group.Key}: {group.Count()} fixture images, CER {group.Average(r => r.CharacterError):P1}, focus {group.Count(r => r.FocusHit)}/{group.Count()}, median {group.Select(r => r.Milliseconds).Order().ElementAt(group.Count()/2):0} ms");
        Console.WriteLine("Fixture OCR only; excludes desktop capture and pointer scheduling. Skipped OCR packs: " + string.Join(", ", skipped));
        return 0;
    }
    internal static Bitmap Render(Sample sample, Appearance appearance, Font font, out PixelPoint focus)
    {
        using var metrics = new Bitmap(1, 1);
        using var measure = Graphics.FromImage(metrics);
        var format = (StringFormat)StringFormat.GenericTypographic.Clone();
        SizeF size = measure.MeasureString(sample.Text, font, 4000, format);
        int width = Math.Min(2300, (int)Math.Ceiling(size.Width) + 48), height = Math.Max(80, (int)Math.Ceiling(size.Height) + 48);
        var image = new Bitmap(width, height, PixelFormat.Format32bppArgb);
        using var graphics = Graphics.FromImage(image); graphics.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
        Color background = ColorTranslator.FromHtml(appearance.Background);
        graphics.Clear(background);
        if (appearance.End is { } end) { using var gradient = new LinearGradientBrush(new Rectangle(0, 0, width, height), background, ColorTranslator.FromHtml(end), 0f); graphics.FillRectangle(gradient, 0, 0, width, height); }
        using var foreground = new SolidBrush(ColorTranslator.FromHtml(appearance.Foreground));
        graphics.DrawString(sample.Text, font, foreground, new PointF(24, 24), format);
        format.SetMeasurableCharacterRanges([new CharacterRange(sample.Text.IndexOf(sample.Focus, StringComparison.Ordinal), sample.Focus.Length)]);
        var ranges = graphics.MeasureCharacterRanges(sample.Text, font, new RectangleF(24, 24, 4000, height), format);
        var bounds = ranges[0].GetBounds(graphics); foreach (var range in ranges) range.Dispose(); format.Dispose();
        focus = new((int)(bounds.Left + bounds.Width / 2), (int)(bounds.Top + bounds.Height / 2)); return image;
    }
    internal static string Normalize(string value) => string.Concat(value.Normalize().ToLowerInvariant().EnumerateRunes().Where(Rune.IsLetterOrDigit).Select(r => r.ToString()));
    internal static double Error(string expected, string actual)
    {
        string a = Normalize(expected), b = Normalize(actual); var prior = Enumerable.Range(0, b.Length + 1).ToArray();
        for (int i = 1; i <= a.Length; i++) { var next = new int[b.Length + 1]; next[0] = i; for (int j = 1; j <= b.Length; j++) next[j] = Math.Min(Math.Min(prior[j] + 1, next[j-1] + 1), prior[j-1] + (a[i-1] == b[j-1] ? 0 : 1)); prior = next; }
        return (double)prior[b.Length] / Math.Max(1, a.Length);
    }
}
