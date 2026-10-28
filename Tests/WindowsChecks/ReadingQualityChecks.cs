using Babelstaarnet.Core;
using Babelstaarnet.Windows;
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

internal static class ReadingQualityChecks
{
    internal const string Question = "Får du undervisning om dagen eller om aftenen hos A2B?";
    internal static async Task<int> UnitsAsync()
    {
        int checks = 0; void Check(bool value, string reason) { if (!value) throw new Exception(reason); checks++; }
        var words = new[] { new RecognizedWord("Får", new(70, 40, 25, 17)), new RecognizedWord("du", new(100, 40, 20, 17)), new RecognizedWord("undervisning", new(140, 40, 85, 17)), new RecognizedWord("aft", new(595, 40, 24, 17)) };
        var clipped = new RecognizedLine("Får du undervisning om aft", words);
        Check(AdaptiveCapture.NeedsExpansion([clipped], new(0, 0, 620, 250), new(75, 45)), "A successful focus hit must not hide a clipped sentence at the crop edge.");
        Check(!AdaptiveCapture.NeedsExpansion([clipped with { Text = "Får du undervisning om aftenen?" }], new(0, 0, 620, 250), new(75, 45)), "A complete question at the edge needs no extra capture.");
        string[] pieces = ["1. får = g", "ets\n", "opslagsform: få\n", "forklaring: At modtage noget."];
        string transcript = string.Join('\n', pieces.Select(v => JsonSerializer.Serialize(new { response = v, done = false }))) + "\n" + JsonSerializer.Serialize(new { response = "", done = true });
        var partial = new System.Collections.Generic.List<string>();
        string text = await ContextualGlossClient.ReadGenerationAsync(new StringReader(transcript), CancellationToken.None, partial.Add);
        Check(partial.Count > 0 && partial.All(t => !t.EndsWith("= g")) && ContextualGlossClient.ParseFocus(partial[0], "får").Meaning == "gets", "Publish only complete meaning lines, never a streamed fragment.");
        Check(ContextualGlossClient.ParseFocus(text, "får").Explanation.Length > 0, "Streaming must retain the final Danish explanation.");
        bool rejected = false; try { await ContextualGlossClient.ReadGenerationAsync(new StringReader("{\"response\":\"1. får = sheep\"}"), CancellationToken.None); } catch (IOException) { rejected = true; }
        Check(rejected, "An interrupted model stream must not be accepted as a complete answer.");
        var finish = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var displayed = new System.Collections.Generic.List<string>();
        using var session = new HoverSession(_ => "sheep", (texts, _) => Task.FromResult<System.Collections.Generic.IReadOnlyList<string>>(texts.Select(_ => "sheep").ToArray()), _ => false) { TranslateSentence = false };
        session.ContextProvider = async (_, _, ready) => { var value = new ContextualAnswer(new System.Collections.Generic.Dictionary<string, string> { ["får"] = "gets" }, new("gets", "få", "")); ready(value); await finish.Task; return value; };
        session.Changed += () => displayed.Add(session.Meaning);
        var pending = session.FocusAsync(new(new("Får", default), new(Question, [])));
        Check(session.Meaning == "gets" && session.MeaningStatus == "In context" && !pending.IsCompleted && !displayed.Contains("sheep"), "A cached isolated noun must not flash over the contextual verb; show the streamed answer before explanation completes.");
        finish.SetResult(); await pending;
        return checks;
    }
    internal static async Task<int> ImageAsync(string input, string output)
    {
        using var original = new Bitmap(input);
        var results = new System.Collections.Generic.List<object>();
        foreach (int scale in new[] { 1, 2 })
        {
            using var raster = new Bitmap(original.Width, original.Height, PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(raster)) g.DrawImageUnscaled(original, 0, 0);
            var lines = await new ScreenReader(scale).RecognizeAsync(raster, default, CancellationToken.None);
            string[] source = lines.Where(l => l.Text.Contains("undervisning", StringComparison.OrdinalIgnoreCase)).Select(l => l.Text).ToArray();
            results.Add(new { scale, lines = lines.Select(l => new { l.Text, l.Frame }), source });
            Console.WriteLine($"x{scale}: " + string.Join(" | ", source));
        }
        File.WriteAllText(output, JsonSerializer.Serialize(results, new JsonSerializerOptions { WriteIndented = true })); return 0;
    }
    internal static async Task<int> RunAsync(string output)
    {
        if (!ScreenReader.DanishAvailable) throw new Exception("Danish OCR is required for the installed-engine quality check.");
        var results = new System.Collections.Generic.List<object>();
        foreach (int size in new[] { 14, 16, 18 })
        foreach (int scale in new[] { 1, 2, 3 })
        {
            using var original = new Bitmap(900, 110, PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(original)) using (var font = new Font("Segoe UI", size, GraphicsUnit.Pixel))
            { g.Clear(Color.FromArgb(252, 244, 244)); g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit; g.DrawString(Question, font, Brushes.Black, 14, 36); }
            using var image = new Bitmap(original.Width * scale, original.Height * scale, PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(image)) { g.InterpolationMode = InterpolationMode.HighQualityBicubic; g.DrawImage(original, new Rectangle(0, 0, image.Width, image.Height)); }
            var lines = await new ScreenReader().RecognizeAsync(image, default, CancellationToken.None);
            string text = string.Join(" ", lines.Select(l => l.Text));
            results.Add(new { size, scale, text }); Console.WriteLine($"{size}px x{scale}: {text}");
        }
        File.WriteAllText(output, JsonSerializer.Serialize(results, new JsonSerializerOptions { WriteIndented = true })); return 0;
    }
}
