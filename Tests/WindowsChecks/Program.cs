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
using System.Windows.Interop;

internal static class Program
{
    private static int checks;
    private static void Check(bool condition, string description)
    {
        if (!condition) throw new Exception(description);
        checks++;
    }

    private static async Task ThrowsAsync<T>(Func<Task> action, string description) where T : Exception
    {
        try { await action(); }
        catch (T) { checks++; return; }
        throw new Exception(description);
    }

    public static async Task<int> Main(string[] arguments)
    {
        Ui.ErrorRaised = error => throw new InvalidOperationException("A UI action failed.", error);
        if (arguments.Length == 3 && arguments[0] == "--ocr-image") return await ReadingQualityChecks.ImageAsync(arguments[1], arguments[2]);
        if (arguments.Length == 2 && arguments[0] == "--reading-quality") return await ReadingQualityChecks.RunAsync(arguments[1]);
        if (arguments.Contains("--context-check")) return await ContextualEngineChecks.RunAsync();
        if (arguments.Length == 2 && arguments[0] == "--hover-benchmark")
            return HoverPipelineBenchmark.Run(arguments[1]);
        if (arguments.Length == 2 && arguments[0] == "--render-ui")
            return UiRendering.Run(arguments[1]);
        if (arguments.Length == 2 && arguments[0] == "--benchmark")
            return await PerformanceBenchmark.RunAsync(arguments[1]);
        string temporary = Path.Combine(Path.GetTempPath(), "Babelstaarnet-checks-" + Guid.NewGuid());
        Directory.CreateDirectory(temporary);
        try
        {
            if (arguments.Contains("--window-lifecycle"))
            {
                Console.WriteLine($"Passed {WindowLifecycleChecks.Run(temporary)} window lifecycle checks."); return 0;
            }
            GeometryChecks();
            MacLayoutChecks();
            ReadingContextChecks();
            HoverScheduleChecks();
            CaptureVisibilityChecks();
            VocabularyChecks(temporary);
            checks += ParityChecks.Run(temporary);
            checks += ReadingParityChecks.Run(temporary);
            checks += await SharedPolicyChecks.RunAsync(temporary);
            checks += NativeExperienceChecks.Run(temporary);
            checks += WindowLifecycleChecks.Run(temporary);
            await HoverSessionChecks();
            checks += await ReadingParityChecks.SessionAsync();
            await WorkerChecks(temporary);
            await RealEngineChecks();
            checks += await ReadingQualityChecks.UnitsAsync();
            checks += await AdaptiveNewsChecks.RunAsync(temporary);
            await OcrChecks();
            await SpeechChecks();
            await NeuralSpeechChecks();
            Console.WriteLine($"Passed {checks} Windows checks.");
            return 0;
        }
        catch (Exception error) { Console.Error.WriteLine(error); return 1; }
        finally { Directory.Delete(temporary, recursive: true); }
    }

    private static void MacLayoutChecks()
    {
        Check(OverlayLayout.WordWidth == 280 && OverlayLayout.SentenceWidth == 420, "Panel widths must match the Mac source metrics.");
        var cases = new[]
        {
            (new PixelRect(610, 430, 72, 24), new PixelRect(430, 426, 520, 32), new PixelRect(0, 0, 1440, 900)),
            (new PixelRect(1450, 700, 80, 22), new PixelRect(410, 600, 1130, 200), new PixelRect(0, 0, 1920, 1200)),
            (new PixelRect(420, 650, 70, 24), new PixelRect(8, 650, 884, 28), new PixelRect(0, 0, 900, 700)),
            (new PixelRect(420, 14, 70, 24), new PixelRect(8, 12, 884, 28), new PixelRect(0, 0, 900, 700)),
            (new PixelRect(-1100, -180, 80, 24), new PixelRect(-1600, -190, 800, 50), new PixelRect(-1920, -400, 1920, 1080))
        };
        foreach (var (word, source, screen) in cases)
        {
            var pair = OverlayLayout.Place(word, source, new(280, 96), new(420, 100), screen);
            Check(pair is not null, "Both panels must find a safe position at screen and paragraph edges.");
            Check(!OverlayLayout.Intersects(pair!.Word, source) && !OverlayLayout.Intersects(pair.Sentence, source), "Neither panel may cover any source line.");
            Check(!OverlayLayout.Intersects(pair.Word, pair.Sentence) && pair.Word.Bottom < pair.Sentence.Y, "The word panel must remain above the separate sentence panel.");
            foreach (var panel in new[] { pair.Word, pair.Sentence })
                Check(panel.X >= screen.X && panel.Y >= screen.Y && panel.Right <= screen.Right && panel.Bottom <= screen.Bottom, "Both panels must stay within the display.");
            var rule = OverlayLayout.FocusRule(word);
            Check(rule.Y >= word.Bottom + 2 && rule.Width == word.Width + 2, "The focus rule must underline the actual word without covering it.");
        }
    }

    private static void ReadingContextChecks()
    {
        var firstWord = new RecognizedWord("milli-", new(540, 200, 80, 30));
        var first = new RecognizedLine("Le Pen truer med at tilbageholde milli-", [new("Le", new(20, 200, 30, 30)), firstWord]);
        var secondWord = new RecognizedWord("arder", new(20, 242, 80, 30));
        var second = new RecognizedLine("arder i EU-bidrag", [secondWord, new("EU-bidrag", new(140, 242, 140, 30))]);
        var sidebar = new RecognizedLine("Andre nyheder", [new("Andre", new(850, 240, 160, 30))]);
        var combined = ReadingContext.Assemble(new(firstWord, first), [first, second, sidebar]);
        Check(combined.Word.Text == "milliarder" && combined.Line.Text.Contains("milliarder i EU-bidrag"), "Wrapped Danish compounds must be restored before translation and pronunciation.");
        Check(!combined.Line.Text.Contains("Andre"), "Adjacent columns must not join the sentence.");
        Check(OverlayLayout.SourceFrame(combined).Bottom == 272, "Panel placement must protect every line of a wrapped headline.");
        var fromSecond = ReadingContext.Assemble(new(secondWord, second), [first, second]);
        Check(fromSecond.Word.Text == "milliarder", "Hovering either half of a wrapped compound must pronounce the full word.");
        var words = new RecognizedLine("Jeg spiser æbler.", []);
        var tokens = BridgePresentation.Tokens(new(new("æbler", new()), words), new Dictionary<string, string> { ["aebler"] = "apples" }, _ => false);
        Check(tokens.Select(t => t.Text).SequenceEqual(new[] { "Jeg", "spiser", "apples." }) && tokens[^1].English && tokens[^1].Focus, "Sentence panels must preserve punctuation and actual substitution metadata.");
    }

    private static void HoverScheduleChecks()
    {
        var now = DateTimeOffset.UtcNow;
        var point = new PixelPoint(100, 100);
        Check(HoverScanPolicy.ShouldScan(point, null, now.AddMilliseconds(-120), now, now),
            "A settled first hover must scan without waiting for a refresh interval.");
        Check(HoverScanPolicy.ShouldScan(new(200, 100), point, now.AddMilliseconds(-120), now.AddMilliseconds(-140), now),
            "A new word must not wait 1.5 seconds after the preceding scan.");
        Check(!HoverScanPolicy.ShouldScan(point, point, now.AddSeconds(-1), now.AddMilliseconds(-140), now),
            "An unchanged hover must retain the idle refresh limit.");
        Check(!HoverScanPolicy.ShouldScan(new(200, 100), point, now.AddMilliseconds(-30), now.AddSeconds(-2), now),
            "Pointer motion must settle before an OCR scan starts.");
        Check(HoverScanPolicy.ShouldScan(point, point, now.AddSeconds(-1), now.AddMilliseconds(-180), now, hasHit: false),
            "A missed hit must retry within 150 ms instead of waiting for the idle refresh interval.");
        Check(!HoverScanPolicy.Moved(point, new(102, 99)), "Small pointer jitter must not cancel an in-flight word.");
    }

    private static void CaptureVisibilityChecks()
    {
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            try
            {
                using var panels = new OverlayWindow();
                Check(panels.CheckNativeSurfaces(), "All three native surfaces must be hidden, nonactivating, and the focus mark must allow clicks through.");
                // A hidden, owned top-level window exercises real display
                // affinity without capturing or interacting with the desktop.
                using var window = new HwndSource(new HwndSourceParameters("Babelstaarnet capture check")
                {
                    WindowStyle = unchecked((int)0x80000000), Width = 100, Height = 100
                });
                Check(NativeMethods.GetWindowDisplayAffinity(window.Handle, out uint before) && before == 0,
                    "Bubbles must be capturable by default.");
                CaptureVisibility.Run(window.Handle, () =>
                {
                    Check(NativeMethods.GetWindowDisplayAffinity(window.Handle, out uint during) && during == 0x11,
                        "The reader must exclude its own bubble while copying pixels.");
                }, () => throw new Exception("Owned window affinity unexpectedly failed."), () => { });
                Check(NativeMethods.GetWindowDisplayAffinity(window.Handle, out uint after) && after == 0,
                    "External screenshots must see the bubble after the pixel copy.");
                try
                {
                    CaptureVisibility.Run(window.Handle, () => throw new IOException("capture failed"), () => { }, () => { });
                    throw new Exception("Capture failures must propagate.");
                }
                catch (IOException) { checks++; }
                Check(NativeMethods.GetWindowDisplayAffinity(window.Handle, out uint afterFailure) && afterFailure == 0,
                    "Screenshot visibility must be restored after a failed capture.");
                bool hidden = false;
                bool restored = false;
                try
                {
                    CaptureVisibility.Run(IntPtr.Zero, () =>
                    {
                        Check(hidden, "The fallback must hide the overlay before copying pixels.");
                        throw new IOException("fallback capture failed");
                    }, () => hidden = true, () => restored = true);
                }
                catch (IOException) { }
                Check(restored, "The fallback must restore the overlay even if capture fails.");
            }
            catch (Exception error) { failure = error; }
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join();
        if (failure is not null) throw new Exception("Capture visibility checks failed.", failure);
    }

    private static void GeometryChecks()
    {
        Check(ReadingPolicy.Key("“Æblegrød!”") == "æblegrød", "Danish learning keys must match macOS Unicode normalization.");
        var word = new RecognizedWord("æbler", new(-100, 120, 60, 24));
        var line = new RecognizedLine("Jeg spiser æbler.", [word]);
        Check(ReadingPolicy.HitTest([line], new(-80, 132))?.Word == word, "Negative monitor origins must hit.");
        Check(ReadingPolicy.HitTest([line], new(0, 132)) is null, "Empty space must not hit.");
        var adjacent = new RecognizedWord("og", new(-40, 120, 24, 24));
        Check(ReadingPolicy.HitTest([new RecognizedLine("æbler og", [word, adjacent])], new(-39, 132))?.Word == adjacent,
            "Real word hits must beat tolerance from the previous word.");
        Check(ReadingPolicy.Bridge(line.Text, new Dictionary<string, string> { ["spiser"] = "eat", ["aebler"] = "apples" },
            key => key == "jeg") == "Jeg eat apples.", "The reading bridge must preserve order and punctuation.");
        Check(ReadingPolicy.Bridge(line.Text, new Dictionary<string, string> { ["aebler"] = "apples" },
            _ => true) == line.Text, "Known words must remain Danish.");
        foreach (var screen in new[] { new PixelRect(0, 0, 1920, 1080), new PixelRect(-2560, -400, 2560, 1440), new PixelRect(0, 0, 800, 600) })
            foreach (var pointer in new[] { new PixelPoint(screen.X, screen.Y), new PixelPoint(screen.Right - 1, screen.Bottom - 1) })
            {
                var crop = PixelRect.CaptureAround(pointer, screen);
                Check(crop.X >= screen.X && crop.Y >= screen.Y && crop.Right <= screen.Right && crop.Bottom <= screen.Bottom,
                    "Capture must stay inside the chosen monitor.");
                foreach (double scale in new[] { 1.0, 1.5, 2.0 })
                {
                    int width = Math.Min((int)(480 * scale), screen.Width);
                    int height = Math.Min((int)(240 * scale), screen.Height);
                    var location = PixelRect.PlaceBubble(new(pointer.X, pointer.Y, 40, 24), width, height, screen);
                    Check(location.X >= screen.X && location.Y >= screen.Y && location.X + width <= screen.Right && location.Y + height <= screen.Bottom,
                        "Bubbles must remain visible at monitor edges and different DPI scales.");
                }
            }
    }

    private static void VocabularyChecks(string temporary)
    {
        string path = Path.Combine(temporary, "vocabulary.json");
        var store = new VocabularyStore(path);
        var now = DateTimeOffset.Parse("2026-10-15T10:00:00Z");
        Check(store.LeaveInDanish("jeg"), "Danish structural words start known.");
        store.Save("æbler", "apples", "Jeg spiser æbler, \"nu\".", now);
        store.Save("æbler", "æbler", "", now);
        Check(store.Saved.Single().Meaning == "apples", "An empty/repeated gloss must not overwrite a useful meaning.");
        Check(store.Csv().Contains("\"Jeg spiser æbler, \"\"nu\"\".\""), "CSV must escape commas and quotes.");
        Check(store.Saved.Single().DueAt == now.AddHours(1), "An unknown saved word is due in one hour.");
        store.Mark("æbler", true, now);
        Check(store.LeaveInDanish("æbler"), "Known feedback must remove English scaffolding.");
        store.Mark("jeg", false, now);
        Check(!store.LeaveInDanish("jeg"), "Explicit unknown feedback overrides the structural prior.");
        store.Review("æbler", true, now);
        Check(store.Saved.Single().DueAt == now.AddDays(60), "Mastered review interval is sixty days.");
        store.Review("æbler", false, now);
        Check(store.Saved.Single().DueAt == now.AddHours(1), "A missed review resets the interval.");
        var restored = new VocabularyStore(path);
        Check(restored.Saved.Single().Meaning == "apples" && !restored.LeaveInDanish("æbler"), "Learning and meanings must survive restart.");
        store.Observe("læser", "Hun læser her.", now);
        for (int i = 0; i < 10; i++) store.Observe("læser", "Hun læser her.", now.AddMinutes(i));
        store.Flush();
        var progress = JsonSerializer.Deserialize<VocabularyEntry[]>(File.ReadAllText(path))!.Single(e => e.Key == "læser");
        Check(progress.SpacedEncounters == 1, "Repeated hovering must not count as learning.");
        for (int i = 1; i <= 7; i++) store.Observe("læser", $"Hun læser tekst {i}.", now.AddDays(i));
        // Different contexts keep the same Mac spacing policy.
        for (int i = 1; i <= 7; i++) store.Observe("læser", "læser " + new string('a', i), now.AddDays(10 + i));
        Check(store.LeaveInDanish("læser"), "Spaced encounters in different contexts should fade English help.");
        Check(!store.IsKnown("læser"), "Passive fading must keep the focused English safety net until a word is explicitly known, as on Mac.");
        store.Flush();
        string broken = Path.Combine(temporary, "broken.json");
        File.WriteAllText(broken, "broken data");
        try { _ = new VocabularyStore(broken); throw new Exception("Corrupt data must be reported."); }
        catch (JsonException) { checks++; }
        Check(File.ReadAllText(broken) == "broken data", "Corrupt learning data must be preserved.");
    }

    private static async Task HoverSessionChecks()
    {
        var delayed = new TaskCompletionSource<IReadOnlyList<string>>(TaskCreationOptions.RunContinuationsAsynchronously);
        var spoken = new List<string>();
        int presentations = 0;
        using var session = new HoverSession(word => word == "mælk" ? "milk" : null,
            (words, token) => delayed.Task.WaitAsync(token), _ => true);
        session.Changed += () => presentations++;
        session.ReadAloud += spoken.Add;
        HoveredText Hit(string word, int x) => new(new(word, new(x, 20, 70, 24)), new(word, []));
        var first = session.FocusAsync(Hit("æbler", 10));
        Check(session.Loading && presentations == 1, "Recognition must present before a cold translation finishes.");
        Check(spoken.SequenceEqual(new[] { "æbler" }), "Recognition must request automatic Danish speech before translation finishes.");
        var second = session.FocusAsync(Hit("mælk", 100));
        Check(session.Meaning == "milk" && !session.Loading, "A cached next word must appear without waiting for the abandoned answer.");
        delayed.SetResult(new[] { "apples" });
        await first;
        Check(session.Current!.Word.Text == "mælk" && session.Meaning == "milk", "A late old answer must never replace the next word.");
        await session.FocusAsync(Hit("mælk", 100));
        Check(spoken.Count == 2, "Refreshing the same word must not repeat its pronunciation.");
        session.Clear(); await second;
        Check(session.Current is null, "Clearing a hover must prevent late updates.");
        var batches = new List<int>();
        using var prefetch = new HoverSession(_ => null, (words, _) =>
        { batches.Add(words.Count); return Task.FromResult<IReadOnlyList<string>>(words.Select(w => "en:" + w).ToArray()); }, _ => false);
        await prefetch.FocusAsync(new(new("æbler", new(0, 0, 50, 20)), new("æbler mælk brød", [])));
        Check(batches.SequenceEqual(new[] { 1, 2 }), "Optional context must use bounded small batches after the focused word.");
        batches.Clear(); prefetch.Clear(); prefetch.TranslateSentence = false;
        await prefetch.FocusAsync(new(new("venner", new(0, 0, 50, 20)), new("venner læser avisen", [])));
        Check(batches.SequenceEqual(new[] { 1 }), "Word-only mode must not spend work translating a hidden sentence panel.");
        batches.Clear(); prefetch.Clear(); prefetch.TranslateMeaning = false;
        string? speechOnly = null; prefetch.ReadAloud += word => speechOnly = word;
        await prefetch.FocusAsync(new(new("mælk", new(0, 0, 50, 20)), new("mælk brød", [])));
        Check(batches.Count == 0 && speechOnly == "mælk", "Speech-only mode must request Danish audio without running translation.");
    }

    private static async Task WorkerChecks(string temporary)
    {
        string python = Environment.GetEnvironmentVariable("BABELSTAARNET_TEST_PYTHON") ?? "";
        if (!File.Exists(python)) throw new Exception("Set BABELSTAARNET_TEST_PYTHON to a Python executable for worker checks.");
        using var client = new ArgosClient(python, Path.Combine(AppContext.BaseDirectory, "fake_worker.py"), temporary);
        var unicode = await client.TranslateAsync(["æblegrød", "smør", "æblegrød"], CancellationToken.None);
        Check(unicode.SequenceEqual(new[] { "en:æblegrød", "en:smør", "en:æblegrød" }), "Worker UTF-8 and duplicate requests must round-trip.");
        var parallel = await Task.WhenAll(Enumerable.Range(0, 4).Select(i => client.TranslateAsync([$"text-{i}"], CancellationToken.None)));
        Check(parallel.Select((result, i) => result.Single() == $"en:text-{i}").All(x => x), "Concurrent requests must not consume one another's replies.");
        using var cancellation = new CancellationTokenSource(TimeSpan.FromMilliseconds(150));
        var watch = Stopwatch.StartNew();
        await ThrowsAsync<OperationCanceledException>(() => client.TranslateAsync(["__slow__"], cancellation.Token), "A stale hover must stop waiting promptly.");
        Check(watch.Elapsed < TimeSpan.FromSeconds(5), "Cancellation must not wait for worker exit.");
        Check((await client.TranslateAsync(["recovered"], CancellationToken.None)).Single() == "en:recovered", "A late reply must never be consumed by the next hover.");
        Check(client.WorkerStarts == 1, "Moving the pointer must not restart the loaded model.");
        Check(client.TryGetCached("__slow__", out string completed) && completed == "en:__slow__",
            "A canceled hover's completed result must be available from the cache.");
        var inFlight = client.TranslateAsync(["__slow_queue__"], CancellationToken.None);
        var cachedWhileBusy = client.TranslateAsync(["smør"], CancellationToken.None);
        Check(cachedWhileBusy.IsCompletedSuccessfully && (await cachedWhileBusy).Single() == "en:smør", "Cached translation must bypass a busy worker's inference queue.");
        using var queuedCancellation = new CancellationTokenSource(TimeSpan.FromMilliseconds(30));
        await ThrowsAsync<OperationCanceledException>(() => client.TranslateAsync(["__exit__"], queuedCancellation.Token),
            "A queued stale hover must be canceled before it can reach the pipe.");
        await inFlight;
        await client.WarmAsync(CancellationToken.None);
        Check(client.WorkerStarts == 1, "Canceled queued hovers and repeated warmup must preserve the existing worker.");
        await ThrowsAsync<IOException>(() => client.TranslateAsync(["__bad_count__"], CancellationToken.None), "Incomplete worker responses must fail.");
        await ThrowsAsync<IOException>(() => client.TranslateAsync(["__exit__"], CancellationToken.None), "Worker startup failure must not hang.");
        Check((await client.TranslateAsync(["__stderr__"], CancellationToken.None)).Single() == "en:__stderr__", "Large stderr output must not deadlock the worker.");
        using var deadlineClient = new ArgosClient(python, Path.Combine(AppContext.BaseDirectory, "fake_worker.py"), temporary,
            requestTimeout: TimeSpan.FromSeconds(1));
        await ThrowsAsync<TimeoutException>(() => deadlineClient.TranslateAsync(["__hang__"], CancellationToken.None),
            "A genuinely hung model must still time out and be discarded.");
        Check((await deadlineClient.TranslateAsync(["after-timeout"], CancellationToken.None)).Single() == "en:after-timeout",
            "A worker must recover after its own deadline expires.");
        Check(deadlineClient.WorkerStarts == 2, "A timed-out worker must be replaced.");
        var fill = Enumerable.Range(0, 2048).Select(i => "cache-" + i).ToArray();
        await client.TranslateAsync(fill, CancellationToken.None);
        var rollover = await client.TranslateAsync([fill[0], "after-cache-limit"], CancellationToken.None);
        Check(rollover.SequenceEqual(new[] { "en:cache-0", "en:after-cache-limit" }),
            "Cache rollover must retain both cached and newly translated words in the current response.");
        client.Dispose();
        using var reopened = new ArgosClient(python, Path.Combine(AppContext.BaseDirectory, "fake_worker.py"), temporary);
        Check((await reopened.TranslateAsync(["after-cache-limit"], CancellationToken.None)).Single() == "en:after-cache-limit" && reopened.WorkerStarts == 0,
            "A repeated word after restart must load from persistent memory without starting Python.");
    }

    private static async Task RealEngineChecks()
    {
        string? directory = Environment.GetEnvironmentVariable("BABELSTAARNET_ARGOS_TEST_DATA");
        if (string.IsNullOrEmpty(directory)) return;
        using var client = new ArgosClient(Path.Combine(directory, "argos-venv", "Scripts", "python.exe"),
            AppPaths.Bridge, directory);
        var translated = await client.TranslateAsync(["æbler", "Jeg spiser æbler."], CancellationToken.None);
        Check(translated.Count == 2 && translated.All(text => text.Contains("apple", StringComparison.OrdinalIgnoreCase)),
            "The real Windows engine must translate Danish words and sentences using the installed offline model.");
        Console.WriteLine("Real Argos model translation passed.");
        var start = new ProcessStartInfo(Path.Combine(directory, "argos-venv", "Scripts", "python.exe"))
        {
            UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true
        };
        foreach (string argument in new[] { "-I", "-X", "utf8", Path.Combine(AppContext.BaseDirectory, "word_engine_checks.py"), AppPaths.Bridge, directory })
            start.ArgumentList.Add(argument);
        using var reference = Process.Start(start)!;
        var output = reference.StandardOutput.ReadToEndAsync();
        var errors = reference.StandardError.ReadToEndAsync();
        await reference.WaitForExitAsync();
        string details = await errors;
        Check(reference.ExitCode == 0, "The lightweight worker must preserve the full Argos word meanings: " + details);
        Console.WriteLine("Argos word parity: " + (await output).Trim());
    }

    private static async Task NeuralSpeechChecks()
    {
        string? data = Environment.GetEnvironmentVariable("BABELSTAARNET_ARGOS_TEST_DATA");
        if (data is null) return;
        using var engine = new NeuralSpeechEngine(data);
        if (!engine.IsAvailable) { Console.WriteLine("Local neural voice fixture skipped: model not installed."); return; }
        byte[] wav = await engine.SynthesizeAsync("rødgrød med fløde", CancellationToken.None);
        Check(wav.Length > 44 && wav.AsSpan(0, 4).SequenceEqual("RIFF"u8), "The real Danish neural worker must return local WAV audio.");
        await engine.SynthesizeAsync("æbler", CancellationToken.None);
        Check(engine.WorkerStarts == 1, "The neural model must remain resident across words.");
        using var canceled = new CancellationTokenSource(); canceled.Cancel();
        await ThrowsAsync<OperationCanceledException>(() => engine.SynthesizeAsync("forældet", canceled.Token), "A stale queued voice request must not reach the model.");
        using var playback = new SpeechService(muted: true, engine: new NeuralSpeechEngine(data));
        await playback.WarmAsync(); await playback.SpeakAsync("æbler"); await playback.SpeakAsync("æbler");
        Check(playback.Syntheses == 1 && playback.EngineId.StartsWith("piper:"), "The default neural engine must play and cache the accepted voice independently of Windows TTS.");
        playback.SelectEngine(new WindowsDanishEngine());
        Check(playback.EngineId == "windows:da-DK", "Offline voice engines must be replaceable without changing hover logic.");
        Console.WriteLine("Real offline Danish neural speech and playback passed.");
    }

    private static async Task SpeechChecks()
    {
        if (!SpeechService.DanishAvailable)
        {
            Console.WriteLine("Danish speech fixture skipped: a Danish Windows voice is not installed.");
            return;
        }
        using var stream = await SpeechService.SynthesizeAsync("æbler");
        Check(stream.Size > 44, "A Danish voice must synthesize nonempty local audio.");
        using var player = new Windows.Media.Playback.MediaPlayer { AutoPlay = false };
        using var source = Windows.Media.Core.MediaSource.CreateFromStream(stream, stream.ContentType);
        player.Source = source;
        Check(player.Source is not null, "The desktop media player must accept the synthesized audio stream.");
        player.Source = null;
        using var service = new SpeechService(muted: true, engine: new WindowsDanishEngine());
        await service.WarmAsync();
        await service.SpeakAsync("æbler");
        await service.SpeakAsync("æbler");
        Check(service.Syntheses == 1, "Pronunciation must actually enter Playing, reusing the warm audio cache.");
        service.Stop();
    }

    private static async Task OcrChecks()
    {
        if (!ScreenReader.DanishAvailable)
        {
            Console.WriteLine("Danish OCR fixture skipped: the Windows Danish OCR language pack is not installed.");
            return;
        }
        foreach (var background in new[] { Color.White, Color.FromArgb(252, 244, 244), Color.FromArgb(27, 29, 35) })
        {
            using var small = new Bitmap(900, 100);
            using (var g = Graphics.FromImage(small)) using (var font = new Font("Segoe UI", 14, GraphicsUnit.Pixel))
            { g.Clear(background); g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit; g.DrawString(ReadingQualityChecks.Question, font, background.R < 50 ? Brushes.White : Brushes.Black, 14, 32); }
            var question = await new ScreenReader().RecognizeAsync(small, new(-1000, 200), CancellationToken.None);
            string text = string.Join(" ", question.Select(l => l.Text));
            Check(text.Contains("Får", StringComparison.Ordinal) && text.Contains("A2B", StringComparison.Ordinal) && text.Contains("aftenen"), "Small Danish question fixtures must retain å, the complete clause and A2B on light/dark pages.");
        }
        using var bitmap = new Bitmap(800, 110);
        using (var graphics = Graphics.FromImage(bitmap))
        using (var font = new Font("Segoe UI", 28))
        {
            graphics.Clear(Color.White);
            graphics.DrawString("Jeg spiser æbler.", font, Brushes.Black, 20, 20);
        }
        var reader = new ScreenReader();
        var lines = await reader.RecognizeAsync(bitmap, new(-1200, 50), CancellationToken.None);
        Check(string.Join(" ", lines.Select(l => l.Text)).Contains("æbler", StringComparison.OrdinalIgnoreCase), "Windows OCR must retain Danish diacritics.");
        Check(lines.SelectMany(l => l.Words).All(w => w.Bounds.X < 0 && w.Bounds.Y >= 50), "OCR word coordinates must include the capture's physical origin.");
        using (var patch = bitmap.Clone(new Rectangle(20, 20, 400, 60), System.Drawing.Imaging.PixelFormat.Format32bppArgb))
        {
            Check(reader.MatchesSnapshot(patch, new(-1180, 70)), "Fresh matching line pixels must reuse the OCR snapshot.");
            patch.SetPixel(0, 0, Color.Black);
            Check(!reader.MatchesSnapshot(patch, new(-1180, 70)), "A changed line must invalidate snapshot hit testing.");
            Check(!reader.MatchesSnapshot(patch, new(-1180, 71)), "Shifted pixels must never reuse old word positions.");
        }
        var repeated = await reader.RecognizeAsync(bitmap, new(-1200, 50), CancellationToken.None);
        Check(ReferenceEquals(lines, repeated), "Unchanged screen pixels must reuse the recognized snapshot.");
        using (var graphics = Graphics.FromImage(bitmap))
        using (var font = new Font("Segoe UI", 28))
        {
            graphics.Clear(Color.White);
            graphics.DrawString("Det er mælk.", font, Brushes.Black, 20, 20);
        }
        var changed = await reader.RecognizeAsync(bitmap, new(-1200, 50), CancellationToken.None);
        Check(string.Join(" ", changed.Select(l => l.Text)).Contains("mælk", StringComparison.OrdinalIgnoreCase),
            "Changed screen pixels must invalidate the OCR cache.");
        var shifted = await reader.RecognizeAsync(bitmap, new(-800, 50), CancellationToken.None);
        Check(shifted.SelectMany(l => l.Words).First().Bounds.X == changed.SelectMany(l => l.Words).First().Bounds.X + 400,
            "Identical pixels at a new screen origin must use the new physical coordinates.");
        using var large = new Bitmap((int)Windows.Media.Ocr.OcrEngine.MaxImageDimension + 128, 150);
        using (var graphics = Graphics.FromImage(large))
        using (var font = new Font("Segoe UI", 28))
        { graphics.Clear(Color.White); graphics.DrawString("Jeg spiser æbler.", font, Brushes.Black, large.Width - 600, 20); }
        var wide = await reader.RecognizeAsync(large, new(-large.Width, 300), CancellationToken.None);
        using var referenceCrop = large.Clone(new Rectangle(large.Width - 600, 0, 600, 150), System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        var reference = await reader.RecognizeAsync(referenceCrop, new(-600, 300), CancellationToken.None);
        var referenceWord = reference.SelectMany(l => l.Words).First(w => w.Text.Contains("æbler"));
        Check(wide.SelectMany(l => l.Words).Any(w => w.Text.Contains("æbler") && Math.Abs(w.Bounds.X - referenceWord.Bounds.X) < 12 && Math.Abs(w.Bounds.Y - referenceWord.Bounds.Y) < 12),
            "Oversized monitor snapshots must stay within OCR limits and map results back to physical pixels.");
    }
}
