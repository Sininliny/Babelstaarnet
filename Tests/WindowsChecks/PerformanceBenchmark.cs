using Babelstaarnet.Windows;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

internal static class PerformanceBenchmark
{
    internal static async Task<int> RunAsync(string output)
    {
        string? data = Environment.GetEnvironmentVariable("BABELSTAARNET_ARGOS_TEST_DATA");
        if (string.IsNullOrWhiteSpace(data)) throw new Exception("Set BABELSTAARNET_ARGOS_TEST_DATA first.");
        var values = new Dictionary<string, double>();
        async Task Measure(string name, Func<Task> action)
        {
            var watch = Stopwatch.StartNew();
            await action();
            values[name] = Math.Round(watch.Elapsed.TotalMilliseconds, 1);
            Console.WriteLine($"{name}: {values[name]} ms");
        }
        ArgosClient Client() => new(Path.Combine(data, "argos-venv", "Scripts", "python.exe"), AppPaths.Bridge, data, persistentMemory: false);
        using (var client = Client())
        {
            await Measure("translator_cold_word", async () => await client.TranslateAsync(["situationen"], CancellationToken.None));
            await Measure("translator_warm_word", async () => await client.TranslateAsync(["anspændte"], CancellationToken.None));
            await Measure("translator_warm_line", async () => await client.TranslateAsync(
                ["alvorligt", "næsten", "blive", "mennesker", "sammen", "regeringen", "aftale", "beslutning"], CancellationToken.None));
            await Measure("translator_cached_line", async () => await client.TranslateAsync(
                ["alvorligt", "næsten", "blive", "mennesker", "sammen", "regeringen", "aftale", "beslutning"], CancellationToken.None));
        }
        using (var client = Client())
        {
            using var cancellation = new CancellationTokenSource(TimeSpan.FromMilliseconds(150));
            await Measure("cancel_cold_hover", async () =>
            {
                try { await client.TranslateAsync(["aflysninger"], cancellation.Token); }
                catch (OperationCanceledException) { }
            });
            await Measure("word_after_cancel", async () => await client.TranslateAsync(["beskeder"], CancellationToken.None));
            values["worker_starts_after_cancel"] = client.WorkerStarts;
        }
        if (ScreenReader.DanishAvailable)
        {
            using var bitmap = new Bitmap(1200, 360);
            using (var graphics = Graphics.FromImage(bitmap))
            using (var font = new Font("Segoe UI", 24))
            {
                graphics.Clear(Color.White);
                graphics.DrawString("Jeg spiser æbler, fordi jeg er sulten.", font, Brushes.Black, 20, 130);
            }
            var reader = new ScreenReader();
            await Measure("ocr_cold", async () => await reader.RecognizeAsync(bitmap, new(0, 0), CancellationToken.None));
            var timings = new List<double>();
            for (int i = 0; i < 5; i++)
            {
                var watch = Stopwatch.StartNew();
                await reader.RecognizeAsync(bitmap, new(0, 0), CancellationToken.None);
                timings.Add(watch.Elapsed.TotalMilliseconds);
            }
            values["ocr_warm_median"] = Math.Round(timings.Order().ElementAt(2), 1);
            timings.Clear();
            for (int i = 0; i < 5; i++)
            {
                bitmap.SetPixel(i, 0, Color.Black);
                var watch = Stopwatch.StartNew();
                await reader.RecognizeAsync(bitmap, new(0, 0), CancellationToken.None);
                timings.Add(watch.Elapsed.TotalMilliseconds);
            }
            values["ocr_changed_pixels_median"] = Math.Round(timings.Order().ElementAt(2), 1);
        }
        File.WriteAllText(output, JsonSerializer.Serialize(values, new JsonSerializerOptions { WriteIndented = true }));
        Console.WriteLine($"Benchmark saved: {Path.GetFullPath(output)}");
        return 0;
    }
}
