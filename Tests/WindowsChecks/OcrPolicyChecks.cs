using Babelstaarnet.Core;
using Babelstaarnet.Windows;
using System;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

internal static class OcrPolicyChecks
{
    internal static async Task<int> RunAsync()
    {
        int checks = 0; void Check(bool value, string reason) { if (!value) throw new Exception(reason); checks++; }
        using var json = JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Shared", "reading-contract.json")));
        var ocr = json.RootElement.GetProperty("ocr");
        foreach (var c in ocr.GetProperty("spacing").EnumerateArray()) Check(ReadingPolicy.CompactCjkSpacing(c.GetProperty("text").GetString()!) == c.GetProperty("compact").GetString(), "OCR spacing normalization must preserve Latin labels and join artificial Han spaces.");
        foreach (var c in ocr.GetProperty("scales").EnumerateArray()) Check(Math.Abs(SharedPolicy.bp_ocr_scale(c.GetProperty("height").GetDouble(), c.GetProperty("cjk").GetBoolean() ? 1 : 0, c.GetProperty("width").GetInt32(), c.GetProperty("imageHeight").GetInt32(), c.GetProperty("maximum").GetInt32()) - c.GetProperty("scale").GetDouble()) < .001, "Refinement must respect glyph density, native dimension limits and pixel budgets.");
        foreach (var c in ocr.GetProperty("colours").EnumerateArray())
        {
            byte[] background = c.GetProperty("background").EnumerateArray().Select(e => (byte)e.GetInt32()).ToArray(), foreground = c.GetProperty("foreground").EnumerateArray().Select(e => (byte)e.GetInt32()).ToArray();
            var rgba = new byte[400]; for (int i = 0; i < 100; i++) { Array.Copy(i % 10 == 1 ? foreground : background, 0, rgba, i * 4, 3); rgba[i * 4 + 3] = 255; }
            var gray = new byte[100]; Check(SharedPolicy.bp_ocr_separate(rgba, rgba.Length, 10, 10, 0, gray, gray.Length) == 1 && gray[0] - gray[1] >= 160, "Colour separation must retain faint and equiluminant text as dark antialiased strokes.");
            var bgra = (byte[])rgba.Clone(); for (int i = 0; i < 100; i++) (bgra[i*4], bgra[i*4+2]) = (bgra[i*4+2], bgra[i*4]);
            var reversed = new byte[100]; Check(SharedPolicy.bp_ocr_separate(bgra, bgra.Length, 10, 10, 1, reversed, reversed.Length) == 1 && reversed.SequenceEqual(gray), "BGRA and RGBA must produce the same result on both platforms.");
        }
        var uniform = Enumerable.Repeat((byte)255, 400).ToArray(); var sentinel = Enumerable.Repeat((byte)123, 100).ToArray();
        Check(SharedPolicy.bp_ocr_separate(uniform, 400, 10, 10, 0, sentinel, 100) == 0 && sentinel.All(v => v == 123), "Blank pixels must not turn into invented text.");
        Check(SharedPolicy.bp_ocr_separate(uniform, 4, 10, 10, 0, sentinel, 100) == 0, "Native pixel buffers must validate their lengths before reading.");
        ReadingPolicy.CjkTokenizer = CjkWords.Segment;
        var spaced = new RecognizedLine("我 每 天 学 习", new[] { "我", "每", "天", "学", "习" }.Select((word, i) => new RecognizedWord(word, new(i*20, 10, 16, 18))).ToArray());
        var compact = CjkWords.SegmentLine(spaced);
        Check(compact.Text == "我每天学习" && compact.Words.Any(w => w.Text == "学习" && w.Bounds.X == 60 && w.Bounds.Right == 96), "Joining Chinese words must retain the union of the actual character boxes.");
        foreach (var language in LanguageCatalog.Languages)
        {
            if (!new ScreenReader(language: language).IsAvailable) continue;
            string source = language.Id switch { "da" => "Jeg læser bøger hver dag.", "en" => "I read books every day.", "zh-Hans" => "我每天在家看书和学习。", _ => "我每天在家看書和學習。" };
            string focusWord = language.Id switch { "da" => "bøger", "en" => "books", "zh-Hans" => "学习", _ => "學習" };
            foreach (var style in new[] { new OcrAppearanceChecks.Appearance("paper", "#181818", "#ffffff"), new("dim", "#dadade", "#ededf0"), new("chroma", "#c81e3c", "#2a7b62") })
            {
                using var font = new Font(language.Cjk ? language.Id == "zh-Hant" ? "Microsoft JhengHei" : "Microsoft YaHei" : "Segoe UI", 16, GraphicsUnit.Pixel);
                using var bitmap = OcrAppearanceChecks.Render(new(language.Id, source, focusWord), style, font, out var focus);
                var reader = new ScreenReader(language: language); var lines = await reader.RecognizeAsync(bitmap, default, CancellationToken.None, focus);
                Check(OcrAppearanceChecks.Error(source, string.Join(' ', lines.Select(l => l.Text))) <= .15, "Native fixture OCR must recover ordinary text in " + language.Id + " / " + style.Id);
                Check(ReadingPolicy.HitTest(lines, focus)?.Word.Text == focusWord, "Recovered text must retain focus geometry in " + language.Id + " / " + style.Id);
                int passes = reader.Recognitions; var repeated = await reader.RecognizeAsync(bitmap, default, CancellationToken.None, focus);
                Check(ReferenceEquals(lines, repeated) && reader.Recognitions == passes, "Verified source pixels must reuse the enhanced result without another pass.");
                Check(passes <= 3, "A difficult hover must have a bounded recognition budget.");
            }
        }
        return checks;
    }
}
