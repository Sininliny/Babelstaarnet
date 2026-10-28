using Babelstaarnet.Core;
using Babelstaarnet.Windows;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;

internal static class NativeExperienceChecks
{
    private static int checks;
    private static void Check(bool condition, string message) { if (!condition) throw new Exception(message); checks++; }
    internal static int Run(string directory)
    {
        SharedContract(directory); PixelComparison(); ContextMemory(directory);
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            SynchronizationContext.SetSynchronizationContext(new DispatcherSynchronizationContext());
            async void Start()
            {
                try { ThemesAndPages(directory); VirtualizedBook(directory); await CaptureDispatcherAsync(); }
                catch (Exception error) { failure = error; }
                finally { Dispatcher.CurrentDispatcher.BeginInvokeShutdown(DispatcherPriority.Background); }
            }
            Dispatcher.CurrentDispatcher.BeginInvoke(new Action(Start)); Dispatcher.Run();
        });
        thread.SetApartmentState(ApartmentState.STA); thread.Start(); thread.Join();
        if (failure is not null) throw failure;
        return checks;
    }
    private static void SharedContract(string directory)
    {
        using var data = JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Shared", "reading-contract.json")));
        foreach (var item in data.RootElement.GetProperty("readingUnits").EnumerateArray())
            Check(ReadingPolicy.Words().Matches(item.GetProperty("text").GetString()!).Select(m => m.Value).SequenceEqual(item.GetProperty("words").EnumerateArray().Select(v => v.GetString())), "Reading units must preserve diacritics and A2B while leaving pure numbers alone.");
        foreach (var item in data.RootElement.GetProperty("identities").EnumerateArray())
            Check(ReadingPolicy.Key(item.GetProperty("text").GetString()!) == item.GetProperty("key").GetString(), "Shared Danish identity must agree on both platforms.");
        foreach (var item in data.RootElement.GetProperty("sentences").EnumerateArray())
        {
            string text = item.GetProperty("text").GetString()!;
            Check(SentenceBoundary.StopLocations(text).Count == item.GetProperty("stops").GetInt32(), "Shared sentence stops must agree on both platforms.");
            Check(SentenceBoundary.EndsSentence(text) == item.GetProperty("ends").GetBoolean(), "Shared sentence ending must agree on both platforms.");
        }
        foreach (var item in data.RootElement.GetProperty("learningPresentation").EnumerateArray())
        {
            int B(string name) => item.GetProperty(name).GetBoolean() ? 1 : 0;
            Check(SharedPolicy.bp_anchor(item.GetProperty("level").GetInt32(), B("supported"), B("focus"), B("newSense"), B("cooldown"), B("selected")) == B("anchor"), "Shared reading help must remain available without changing a word's level.");
        }
        foreach (var item in data.RootElement.GetProperty("newsReading").EnumerateArray())
        {
            string title = item.GetProperty("title").GetString()!, summary = item.GetProperty("summary").GetString()!;
            var article = new NewsArticle("fixture", title, summary, "https://www.dr.dk/nyheder/fixture", 0, 0);
            Check(NewsReadingSupport.SourceParts(article).SequenceEqual(item.GetProperty("parts").EnumerateArray().Select(p => p.GetString())), "Reading aid must not depend on an RSS description.");
            string[] pieces = NewsReadingSupport.Pieces(title);
            Check(pieces.SequenceEqual(item.GetProperty("pieces").EnumerateArray().Select(p => p.GetString())) && pieces.Select(NewsReadingSupport.Word).SequenceEqual(item.GetProperty("words").EnumerateArray().Select(p => p.ValueKind == JsonValueKind.Null ? null : p.GetString())), "Native word buttons must preserve Danish spelling, punctuation and numbers.");
        }
        foreach (var item in data.RootElement.GetProperty("newsScaffolding").EnumerateArray())
        {
            var article = new NewsArticle("fixture", item.GetProperty("title").GetString()!, "", "https://www.dr.dk/nyheder/fixture", 0, 0);
            using var reader = new NewsReadingSupport(Path.Combine(directory, "scaffold-" + Guid.NewGuid()));
            var levels = item.GetProperty("levels"); var meanings = item.GetProperty("meanings"); var hints = item.GetProperty("hints");
            reader.KnowledgeLevel = word => levels.TryGetProperty(word.ToLowerInvariant(), out var level) ? level.GetInt32() : 0;
            reader.CachedWordMeaning = word => meanings.TryGetProperty(word.ToLowerInvariant(), out var meaning) ? meaning.GetString() : null;
            reader.Translate = (_, _) => throw new Exception("Available dictionary hints need no translation work.");
            reader.PrepareAsync(article).GetAwaiter().GetResult();
            foreach (string word in NewsReadingSupport.Pieces(article.Title).Select(NewsReadingSupport.Word).OfType<string>())
                Check(reader.Gloss(word, article) == (hints.TryGetProperty(word.ToLowerInvariant(), out var hint) ? hint.GetString() : null), "Unfamiliar words get hints; known words and names remain Danish.");
            Check(!reader.IsVisible(article) && reader.Meaning(article) is null, "Default hints must not create a full English alternative.");
        }
        foreach (var item in data.RootElement.GetProperty("newsAdaptive").EnumerateArray())
        {
            var article = new NewsArticle("adaptive", item.GetProperty("title").GetString()!, "", "https://www.dr.dk/nyheder/fixture", 0, 0);
            using var reader = new NewsReadingSupport(Path.Combine(directory, "adaptive-" + Guid.NewGuid()));
            var levels = item.GetProperty("levels"); var meanings = item.GetProperty("meanings");
            reader.WordBands = JsonSerializer.Deserialize<Dictionary<string, int>>(item.GetProperty("bands").GetRawText())!;
            reader.SupportedReading = () => item.TryGetProperty("supported", out var supported) && supported.GetBoolean();
            reader.KnowledgeLevel = word => levels.TryGetProperty(word.ToLowerInvariant(), out var level) ? level.GetInt32() : 0;
            reader.CachedWordMeaning = word => meanings.TryGetProperty(word.ToLowerInvariant(), out var meaning) ? meaning.GetString() : null;
            reader.PrepareAsync(article).GetAwaiter().GetResult();
            var pieces = NewsReadingSupport.Pieces(article.Title);
            string Text() => string.Join(' ', pieces.Select(piece => reader.Presentation(piece, article).Text));
            Check(Text() == item.GetProperty("display").GetString(), "Adaptive news must replace difficult words inline: " + item.GetProperty("id").GetString());
            var targets = pieces.Where(piece => reader.Presentation(piece, article).Mode == 2).Select(NewsReadingSupport.Word).Distinct().ToArray();
            Check(targets.SequenceEqual(item.GetProperty("targets").EnumerateArray().Select(t => t.GetString())) && reader.Ready(article) == item.GetProperty("ready").GetBoolean(), "Only a bounded, reachable common word with ready help may remain as a new target.");
            reader.KnowledgeLevel = _ => 5;
            Check(Text() == item.GetProperty("display").GetString(), "Learning elsewhere must not change the reading plan halfway through a card.");
            if (targets.Length > 0)
            {
                reader.LookupAsync(targets[0]!, article).GetAwaiter().GetResult();
                Check(reader.Selected?.Meaning.Length > 0 && !pieces.Any(piece => NewsReadingSupport.Word(piece) == targets[0] && reader.Presentation(piece, article).Mode == 2), "Requesting help must reveal a target immediately without assigning a replacement target.");
            }
        }
        foreach (var item in data.RootElement.GetProperty("newsPopupSchedule").EnumerateArray())
        {
            int B(string key) => item.GetProperty(key).GetBoolean() ? 1 : 0; int I(string key) => item.GetProperty(key).GetInt32();
            Check(SharedPolicy.bp_news_popup_due(B("enabled"), B("background"), B("optedIn"), B("blocked"), I("hour"), item.GetProperty("elapsed").GetDouble(), I("interval"), I("shown"), I("fresh")) == B("due"), "Shared popup schedule: " + item.GetProperty("id").GetString());
        }
    }
    private static void PixelComparison()
    {
        using var bitmap = new System.Drawing.Bitmap(3840, 2160);
        using (var graphics = System.Drawing.Graphics.FromImage(bitmap)) graphics.Clear(System.Drawing.Color.White);
        var snapshot = PixelSnapshot.Capture(bitmap, new(-1920, -400));
        // Warm native marshalling and tiered JIT before measuring allocations.
        for (int i = 0; i < 10; i++) snapshot.Matches(bitmap, snapshot.Origin);
        long before = GC.GetAllocatedBytesForCurrentThread();
        for (int i = 0; i < 5; i++) Check(snapshot.Matches(bitmap, snapshot.Origin), "Identical 4K pixels must match without OCR.");
        long allocated = GC.GetAllocatedBytesForCurrentThread() - before;
        Console.WriteLine($"Five 4K snapshot comparisons allocated {allocated} managed bytes.");
        // Allow hosted-runtime initialization noise, while still rejecting even
        // one 33 MB pixel buffer. This is an allocation guard, not a JIT budget.
        Check(allocated < 1_000_000, "Repeated 4K snapshot comparison must not allocate another pixel-sized buffer.");
        bitmap.SetPixel(3839, 2159, System.Drawing.Color.Black);
        Check(!snapshot.Matches(bitmap, snapshot.Origin), "A change in the last pixel must invalidate the snapshot.");
        Check(!snapshot.Matches(bitmap, new(-1919, -400)), "Identical dimensions at another origin must not reuse old word coordinates.");
    }
    private static void ContextMemory(string directory)
    {
        string path = Path.Combine(directory, "context-memory.json");
        ContextualMemory.Save(path, new("same-model", new() { ["Han får en gave."] = new() { ["får"] = "receives" } }, new() { ["Han får en gave.\u001ffår"] = new("receives", "få", "At modtage noget.") }));
        var read = ContextualMemory.Load(path, "same-model");
        Check(read.Focuses.Values.Single().Lemma == "få" && read.Sentences.Count == 1, "Focused and partial sentence meanings must survive restart.");
        Check(ContextualMemory.Load(path, "new-model").Focuses.Count == 0, "Different model or prompt stamps must invalidate contextual memory.");
        File.WriteAllText(path, "{\"Stamp\":\"same-model\",\"Sentences\":null,\"Focuses\":null}");
        Check(ContextualMemory.Load(path, "same-model").Focuses.Count == 0, "Malformed contextual memory must not prevent startup.");
    }
    private static void ThemesAndPages(string directory)
    {
        var theme = WindowsTheme.Current; theme.Apply("light", false, false); var brush = Ui.Ink;
        var text = Ui.Text("Theme updates in place"); theme.Apply("dark", true, false);
        Check(ReferenceEquals(brush, text.Foreground) && ((SolidColorBrush)text.Foreground).Color.R > 230, "An existing control must update when Windows appearance changes.");
        Check(Contrast(theme.Ink.Color, theme.Surface.Color) >= 7 && Contrast(theme.Muted.Color, theme.Paper.Color) >= 4.5 && Contrast(theme.OnAccent.Color, theme.Accent.Color) >= 4.5, "Dark typography and accent controls must remain readable.");
        theme.Apply("light", false, false);
        Check(Contrast(theme.Ink.Color, theme.Surface.Color) >= 7 && Contrast(theme.OnAccent.Color, theme.Accent.Color) >= 4.5, "Light typography and accent controls must remain readable.");
        theme.Apply("system", highContrast: true);
        Check(theme.Ink.Color == SystemColors.WindowTextColor && theme.Surface.Color == SystemColors.WindowColor && !theme.Animate, "High contrast must use Windows colors and suppress decorative motion.");
        theme.Apply("light", false, false);
        string preferences = Path.Combine(directory, "appearance.json");
        var model = new ReaderUiModel(new(), new VocabularyStore(Path.Combine(directory, "appearance-words.json")), preferences);
        model.Apply = () => theme.Apply(model.Preferences.Appearance);
        int bookOpens = 0, newsOpens = 0, scheduleOpens = 0; model.OpenBook = () => bookOpens++; model.OpenNews = () => newsOpens++; model.OpenNewsSettings = () => scheduleOpens++;
        var tray = new TrayPanel(model); Layout(tray, 290, 650);
        var book = Descendants<Button>(tray).Single(b => System.Windows.Automation.AutomationProperties.GetName(b) == "Open Word Book");
        book.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Check(bookOpens == 1 && book.IsTabStop && book.Focusable && Descendants<Button>(tray).First() == book, "Word Book must be a primary keyboard-accessible tray action independent of Settings.");
        Descendants<Button>(tray).Single(b => Equals(b.Content, "Read something new")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Descendants<Button>(tray).Single(b => Equals(b.Content, "Scheduled news cards…")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Check(newsOpens == 1 && scheduleOpens == 1, "The themed tray must keep news and scheduling beside Word Book at the first level.");
        using var menu = new TrayMenu(model, () => { });
        Check(menu.Items[0].Name == "word-book" && menu.Items[1].Name == "news" && menu.Items[2].Name == "news-cards", "Native tray first-level menu must expose Word Book, news and scheduling.");
        ((System.Windows.Forms.ToolStripMenuItem)menu.Items[0]).PerformClick();
        Check(bookOpens == 2 && !menu.Visible, "Native menu actions must work without opening Settings or activating a test window.");
        var shell = new SettingsShell(model); Layout(shell, 880, 640);
        foreach (var setting in new[] { "light", "dark", "contrast" })
        {
            theme.Apply(setting == "contrast" ? "system" : setting, setting == "dark", setting == "contrast"); shell.SelectPage("Shortcuts"); Layout(shell, 880, 640);
            foreach (var recorder in Descendants<ShortcutRecorder>(shell))
            {
                var glyph = Descendants<TextBlock>(recorder).First(t => t.Text == recorder.Content.ToString());
                Check(Contrast(((SolidColorBrush)glyph.Foreground).Color, ((SolidColorBrush)recorder.Background).Color) >= 4.5 && recorder.Focusable && recorder.IsTabStop, "Rendered shortcut glyphs must be legible and keyboard accessible in both themes.");
            }
            shell.SelectPage("Appearance"); Layout(shell, 880, 640);
            var box = Descendants<ComboBox>(shell).Single(c => c.Items.Contains("Use Windows setting"));
            var arrow = Descendants<System.Windows.Shapes.Path>(box).First();
            var at = arrow.TranslatePoint(new Point(0, 0), box);
            Check(at.X > box.ActualWidth - 35 && at.X < box.ActualWidth, "A combo arrow must stay in its trailing slot instead of overlapping its label.");
        }
        theme.Apply("light", false, false);
        var navigation = Descendants<ListBox>(shell).Single(); navigation.SelectedItem = navigation.Items.Cast<ListBoxItem>().Single(item => Equals(item.Tag, "Appearance"));
        Check(shell.SelectedPage == "Appearance", "Windows navigation must open its selected settings page.");
        var picker = Descendants<ComboBox>(shell).Single(box => box.Items.Contains("Use Windows setting")); picker.SelectedIndex = 2;
        Check(ReaderPreferences.Load(preferences).Appearance == "dark", "Appearance selection must persist through the real settings callback.");
        theme.Apply("light", false, false);
    }
    private static void VirtualizedBook(string directory)
    {
        string Word(int n) { string word = "ord"; do { word += (char)('a' + n % 26); n /= 26; } while (n > 0); return word; }
        var entries = Enumerable.Range(0, 5000).Select(i => new VocabularyEntry { Key = Word(i), Word = Word(i), Saved = true, Level = i % 2 == 0 ? 4 : 0, SavedAt = DateTimeOffset.Now.AddMinutes(-i) }).ToArray();
        string path = Path.Combine(directory, "large-book.json"); File.WriteAllText(path, JsonSerializer.Serialize(entries));
        var watch = Stopwatch.StartNew(); var book = new WordBookPanel(new VocabularyStore(path), _ => { }, new()); Layout(book, 860, 520);
        var list = Descendants<ListBox>(book).Single();
        Check(list.Items.Count == 5000 && book.RowBuilds < 50, "A 5,000-word book must create only visible rows.");
        int initialRows = book.RowBuilds;
        list.ScrollIntoView(list.Items[^1]); Layout(book, 860, 520);
        Check(book.RowBuilds < 100, "Scrolling to the end must recycle containers instead of constructing the whole book.");
        Descendants<Button>(book).Single(button => Equals(button.Content, "Known")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Check(list.Items.Count == 2500, "Virtualization must retain familiarity filters.");
        Console.WriteLine($"5,000-word book: {initialRows} initial rows, {watch.ElapsedMilliseconds} ms including load, layout, scroll and filter.");
    }
    private static async Task CaptureDispatcherAsync()
    {
        using var overlay = new OverlayWindow(); using var release = new ManualResetEventSlim();
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously); int ui = Environment.CurrentManagedThreadId, worker = ui;
        var task = overlay.CaptureWithoutOverlayAsync(new(0, 0, 10, 10), () => { worker = Environment.CurrentManagedThreadId; entered.SetResult(); release.Wait(TimeSpan.FromSeconds(2)); }, CancellationToken.None);
        await entered.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(Environment.CurrentManagedThreadId == ui && worker != ui && !task.IsCompleted, "Waiting for capture must leave the UI dispatcher available.");
        release.Set(); await task;
    }
    private static double Contrast(Color a, Color b)
    {
        double L(Color c) { double S(byte v) { double n = v / 255.0; return n <= .04045 ? n / 12.92 : Math.Pow((n + .055) / 1.055, 2.4); } return .2126 * S(c.R) + .7152 * S(c.G) + .0722 * S(c.B); }
        double x = L(a), y = L(b); return (Math.Max(x, y) + .05) / (Math.Min(x, y) + .05);
    }
    private static void Layout(FrameworkElement element, double width, double height) { element.Measure(new(width, height)); element.Arrange(new Rect(0, 0, width, height)); element.UpdateLayout(); }
    private static IEnumerable<T> Descendants<T>(DependencyObject root) where T : DependencyObject
    {
        if (root is T item) yield return item;
        for (int i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++) foreach (var child in Descendants<T>(VisualTreeHelper.GetChild(root, i))) yield return child;
    }
}
