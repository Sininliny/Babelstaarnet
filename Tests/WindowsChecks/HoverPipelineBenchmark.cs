using Babelstaarnet.Core;
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
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

internal static class HoverPipelineBenchmark
{
    // Uses the production OCR, hover session, translator, WPF card and audio
    // player. Pixel input is a fixture; it does not read the user's desktop.
    internal static int Run(string output)
    {
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            SynchronizationContext.SetSynchronizationContext(new DispatcherSynchronizationContext());
            async void Start()
            {
                try { await RunAsync(output); }
                catch (Exception error) { failure = error; }
                finally { Dispatcher.CurrentDispatcher.BeginInvokeShutdown(DispatcherPriority.Background); }
            }
            Dispatcher.CurrentDispatcher.BeginInvoke(new Action(Start));
            Dispatcher.Run();
        });
        thread.SetApartmentState(ApartmentState.STA); thread.Start(); thread.Join();
        if (failure is not null) throw failure;
        return 0;
    }

    private static async Task RunAsync(string output)
    {
        string data = Environment.GetEnvironmentVariable("BABELSTAARNET_ARGOS_TEST_DATA") ?? throw new Exception("Set BABELSTAARNET_ARGOS_TEST_DATA first.");
        using var translator = new ArgosClient(Path.Combine(data, "argos-venv", "Scripts", "python.exe"), AppPaths.Bridge, data);
        var reader = new ScreenReader();
        using var speech = new SpeechService(muted: true);
        await Task.WhenAll(translator.WarmAsync(CancellationToken.None), reader.WarmAsync(), speech.WarmAsync());
        using var bitmap = new Bitmap(1200, 180);
        using (var graphics = Graphics.FromImage(bitmap))
        using (var font = new System.Drawing.Font("Segoe UI", 24))
        {
            graphics.Clear(System.Drawing.Color.White);
            graphics.DrawString("anspændte situation alvorligt næsten æbler mælk", font, System.Drawing.Brushes.Black, 20, 60);
        }
        var timings = new List<object>();
        var card = new FloatingSurface(new OverlayCard());
        var wordCard = (OverlayCard)card.Children[1];
        using var session = new HoverSession(word => translator.TryGetCached(word, out var cached) ? cached : null,
            translator.TranslateAsync, _ => true);
        var watch = Stopwatch.StartNew();
        double firstCard = 0, meaning = 0;
        Task audio = Task.CompletedTask;
        session.Changed += () =>
        {
            wordCard.SetContent(session.Current!, session.Meaning, session.Bridge, false, session.Loading, false);
            card.Measure(new System.Windows.Size(280, double.PositiveInfinity));
            card.Arrange(new Rect(0, 0, 280, card.DesiredSize.Height)); card.UpdateLayout();
            var render = new RenderTargetBitmap(280, (int)Math.Ceiling(card.ActualHeight), 96, 96, PixelFormats.Pbgra32); render.Render(card);
            if (firstCard == 0) firstCard = watch.Elapsed.TotalMilliseconds;
            if (!session.Loading && meaning == 0) meaning = watch.Elapsed.TotalMilliseconds;
        };
        session.ReadAloud += text => audio = speech.SpeakAsync(text);
        for (int i = 0; i < 6; i++)
        {
            session.Clear(); firstCard = meaning = 0; watch.Restart();
            await Task.Delay(HoverScanPolicy.SettleDelay);
            var lines = await reader.RecognizeAsync(bitmap, new(0, 0), CancellationToken.None);
            var word = lines.SelectMany(l => l.Words).ElementAt(i);
            var hit = ReadingPolicy.HitTest(lines, new(word.Bounds.X + word.Bounds.Width / 2, word.Bounds.Y + word.Bounds.Height / 2))!;
            var completion = session.FocusAsync(hit);
            await audio;
            double voice = watch.Elapsed.TotalMilliseconds;
            await completion;
            timings.Add(new { word = i + 1, card_ms = Math.Round(firstCard, 1), meaning_ms = Math.Round(meaning, 1), audio_playing_ms = Math.Round(voice, 1) });
        }
        string json = JsonSerializer.Serialize(new { fixture = "In-memory page → OCR → hit → production session → WPF render + muted audio playback; includes 35 ms settle, excludes desktop capture", samples = timings }, new JsonSerializerOptions { WriteIndented = true });
        File.WriteAllText(output, json); Console.WriteLine(json);
    }
}
