using Babelstaarnet.Core;
using Babelstaarnet.Windows;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;

internal static class ParityChecks
{
    private static int checks;
    private static void Check(bool condition, string why) { if (!condition) throw new Exception(why); checks++; }
    internal static int Run(string temporary)
    {
        Preferences(temporary); Learning(temporary); Review();
        Exception? failure = null;
        var thread = new Thread(() => { try { NativeShortcuts(); Icons(); Panels(temporary); } catch (Exception error) { failure = error; } });
        thread.SetApartmentState(ApartmentState.STA); thread.Start(); thread.Join();
        if (failure is not null) throw failure; return checks;
    }
    private static void Preferences(string temporary)
    {
        string path = Path.Combine(temporary, "preferences.json");
        File.WriteAllText(path, "{\"SpeechEngine\":\"windows\",\"ReadAloud\":false}");
        var preferences = ReaderPreferences.Load(path);
        Check(!preferences.ReadAloud && preferences.SpeechEngine == "windows" && preferences.WordMeaning && preferences.WholeSentence && preferences.PowerSaving, "Existing voice preferences must migrate with the Mac panel and reading defaults.");
        Check(preferences.SpeakAfterSeconds == .45 && preferences.Shortcuts.ToggleLearning.Display == "Ctrl+Alt+Z" && preferences.Shortcuts.Known.Display == "1", "Speech delay and bubble shortcuts must use the intended defaults.");
        preferences.WordMeaning = false; preferences.WholeSentence = false; preferences.FollowScreenChanges = false; preferences.SpeakAfterSeconds = 9;
        preferences.Shortcuts = preferences.Shortcuts with { HoldModifier = HoldModifier.Shift, ToggleLearning = new(120, 6) }; preferences.Save(path);
        var restored = ReaderPreferences.Load(path);
        Check(!restored.WordMeaning && !restored.WholeSentence && !restored.FollowScreenChanges && restored.SpeakAfterSeconds == 1.2 && restored.Shortcuts.ToggleLearning.Display == "Ctrl+Shift+F9" && restored.Shortcuts.HoldModifier == HoldModifier.Shift, "All settings and recorded shortcuts must survive restart.");
        Check((HotKeyConfiguration.Defaults with { ToggleLearning = new(90, 0) }).ValidationError() is not null, "Global toggle must not consume an unmodified typing key.");
        Check((HotKeyConfiguration.Defaults with { Known = new(50, 0) }).ValidationError() is not null, "Duplicate actions must be rejected.");
        preferences.SpeakAfterSeconds = double.NaN; preferences.Shortcuts = preferences.Shortcuts with { Known = new(16, 0) }; preferences.Normalize();
        Check(preferences.SpeakAfterSeconds == .45 && preferences.Shortcuts == HotKeyConfiguration.Defaults, "Invalid settings must recover to usable defaults.");
    }
    private static void Learning(string temporary)
    {
        var now = DateTimeOffset.Parse("2026-10-15T10:00:00Z"); string path = Path.Combine(temporary, "parity-vocabulary.json");
        var store = new VocabularyStore(path); store.Save("æbler", "apples", "Jeg spiser æbler.", now.AddDays(-1)); store.Observe("æbler", "Jeg spiser æbler.", now);
        store.Mark("æbler", true, now); store.Mark("æbler", true, now.AddMinutes(1));
        Check(store.Saved.Single().Level == 4, "Repeated Knew in one sitting must not establish mastery.");
        store.Mark("æbler", true, now.AddHours(21));
        Check(store.Saved.Single().Level == 5, "A spaced known confirmation must establish mastery.");
        var savedAt = store.Saved.Single().SavedAt; store.SetMeaning("æbler", "apples, plural");
        Check(store.Saved.Single().SavedAt == savedAt, "Filling meanings must not reorder the book or change its review anchor.");
        string exported = store.ExportProfile(now);
        using var archive = JsonDocument.Parse(exported); var word = archive.RootElement.GetProperty("words")[0];
        Check(word.GetProperty("word").GetString() == "æbler" && !archive.RootElement.GetProperty("exportedAt").GetString()!.Contains('.'), "Mac profile exports require Danish spelling and whole-second ISO dates.");
        var merged = new VocabularyStore(Path.Combine(temporary, "merged-vocabulary.json"));
        merged.ImportProfile(exported, now); string first = merged.ExportProfile(now); merged.ImportProfile(exported, now);
        Check(first == merged.ExportProfile(now), "Importing the same archive twice must be idempotent.");
        Check(merged.TrackedCount == 1 && !merged.Saved.Any() && merged.IsKnown("æbler"), "Learning imports must not manufacture Word Book entries.");
        string before = store.ExportProfile(now);
        var corrupt = JsonSerializer.Deserialize<LearningArchive>(exported, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase })!;
        corrupt.Words = [corrupt.Words[0], new LearningWord { Word = "mælk", KnowledgeLevel = 9, LastSeen = now }];
        try { store.ImportProfile(JsonSerializer.Serialize(corrupt, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase }), now); throw new Exception("An invalid profile must fail."); } catch (InvalidDataException) { checks++; }
        Check(store.ExportProfile(now) == before, "A bad later record must not partially mutate local progress.");
        var older = new LearningArchive { SourceLanguage = "da", ExportedAt = now, Words = [new LearningWord { Word = "æbler", KnowledgeLevel = 0, EncounterCount = 25, LastSeen = now, LastReviewedAt = now.AddDays(-1) }] };
        merged.ImportProfile(JsonSerializer.Serialize(older, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase }), now);
        using var after = JsonDocument.Parse(merged.ExportProfile(now)); var progress = after.RootElement.GetProperty("words")[0];
        Check(merged.IsKnown("æbler") && progress.GetProperty("encounterCount").GetInt32() == 25, "Newest review wins while encounter counts merge by maximum.");
        var entry = new VocabularyEntry { Level = 5, ReviewedAt = now };
        Check(entry.EffectiveLevel(now.AddDays(364)) == 5 && entry.EffectiveLevel(now.AddDays(365)) == 4 && entry.EffectiveLevel(now.AddDays(545)) == 3, "Knowledge must decay with the same retention intervals as Mac.");
        store.ResetLearning();
        Check(store.TrackedCount == 0 && store.Saved.Single().Meaning == "apples, plural" && store.Saved.Single().SavedAt == savedAt, "Reset must keep the entire Word Book while removing learned evidence.");
        store.Mark("æbler", true, now); store.RemoveSaved("æbler");
        Check(!store.Saved.Any() && store.IsKnown("æbler"), "Removing a book entry must retain learning progress.");
        store.Observe("mælk", "Vi drikker mælk.", now); store.Flush();
        Check(new VocabularyStore(path).TrackedCount == 2, "Shutdown flush must preserve batched reading encounters.");
    }
    private static void Review()
    {
        var entry = new VocabularyEntry { Word = "æbler", Key = "æbler" }; var session = new WordReviewSession([entry]);
        session.Answer(true); Check(session.Position == 0, "Review answers are unavailable before the meaning is revealed.");
        session.Revealed = true; session.Answer(false);
        Check(session.Count == 2 && session.Current == entry && !session.Revealed, "A missed word must be asked once more with its answer hidden.");
        session.Revealed = true; session.Answer(false);
        Check(session.Current is null && session.Count == 2 && session.Forgotten == 2, "A twice-missed word must finish the sitting rather than loop forever.");
    }
    private static void NativeShortcuts()
    {
        using var blocker = new HwndSource(new HwndSourceParameters("Babelstaarnet shortcut conflict fixture") { ParentWindow = new IntPtr(-3), Width = 0, Height = 0 });
        const uint modifiers = 7, occupied = 135, available = 134;
        Check(NativeMethods.RegisterHotKey(blocker.Handle, 500, modifiers, occupied), "The isolated Ctrl+Alt+Shift+F24 fixture must be available.");
        try
        {
            using var keys = new HotKeyService();
            var config = HotKeyConfiguration.Defaults with { ToggleLearning = new(available, modifiers) };
            keys.Configure(config); keys.Suspend(true);
            try { keys.Configure(config with { ToggleLearning = new(occupied, modifiers) }); throw new Exception("A conflict while recording must be rejected."); } catch (System.ComponentModel.Win32Exception) { checks++; }
            keys.Suspend(false);
            Check(!NativeMethods.RegisterHotKey(blocker.Handle, 501, modifiers, available), "Failed recording must restore the previous registered shortcut.");
            keys.Suspend(true);
            Check(NativeMethods.RegisterHotKey(blocker.Handle, 501, modifiers, available), "Recording must release the toggle so it can be captured.");
            NativeMethods.UnregisterHotKey(blocker.Handle, 501);
        }
        finally { NativeMethods.UnregisterHotKey(blocker.Handle, 500); }
    }
    private static void Icons()
    {
        foreach (string theme in new[] { "light", "dark" })
            foreach (string state in new[] { "active", "inactive" })
            {
                using var stream = BrandIcons.Resource($"tray-{state}-{theme}.ico"); var decoder = new IconBitmapDecoder(stream, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
                Check(decoder.Frames.Any(f => f.PixelWidth == 16) && decoder.Frames.Any(f => f.PixelWidth == 32) && decoder.Frames.Any(f => f.PixelWidth == 256), "Tray logo must have small and high-DPI resources.");
            }
        Check(((BitmapSource)BrandIcons.AppImage).PixelWidth == 256, "Window and executable branding must use the packaged app logo.");
        using var icons = new BrandIcons();
        Check(icons.Tray(true, true).Handle != icons.Tray(false, true).Handle, "Active and inactive tray logos must be distinct native resources.");
    }
    private static IEnumerable<T> Descendants<T>(DependencyObject root) where T : DependencyObject
    {
        if (root is T item) yield return item;
        for (int i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++)
            foreach (var child in Descendants<T>(VisualTreeHelper.GetChild(root, i))) yield return child;
    }
    private static void Layout(FrameworkElement element, double width, double height)
    { element.Measure(new Size(width, height)); element.Arrange(new Rect(0, 0, width, height)); element.UpdateLayout(); }
    private static void Panels(string temporary)
    {
        var store = new VocabularyStore(Path.Combine(temporary, "ui-vocabulary.json")); var preferences = new ReaderPreferences();
        string preferenceFile = Path.Combine(temporary, "ui-preferences.json"); int applied = 0, toggles = 0, spoken = 0;
        var model = new ReaderUiModel(preferences, store, preferenceFile) { Apply = () => applied++, Toggle = () => toggles++, OcrReady = true, TranslationReady = true, VoiceReady = true };
        var settings = new SettingsPanel(model); Layout(settings, 480, 760);
        var delay = Descendants<Slider>(settings).Single(); double oldDelay = delay.Value;
        Slider.IncreaseSmall.Execute(null, delay);
        Check(delay.Value > oldDelay && ReaderPreferences.Load(preferenceFile).SpeakAfterSeconds == delay.Value, "The rounded speech slider must retain native keyboard commands and persist changes.");
        applied = 0;
        var boxes = Descendants<CheckBox>(settings).ToArray();
        boxes.Single(c => Equals(c.Content, "Word meaning")).IsChecked = false;
        boxes.Single(c => Equals(c.Content, "Whole sentence")).IsChecked = false;
        Check(applied == 2 && !ReaderPreferences.Load(preferenceFile).WordMeaning && !ReaderPreferences.Load(preferenceFile).WholeSentence, "Settings switches must persist independently and invoke reading changes.");
        var follow = boxes.Single(c => Equals(c.Content, "Follow screen changes")); follow.IsChecked = false; model.Notify();
        Check(!boxes.Single(c => Equals(c.Content, "Pause screen reading when idle")).IsEnabled, "Power saving must be disabled while live reading is off.");
        var context = boxes.Single(c => Equals(c.Content, "Translate words in their sentence"));
        Check(!context.IsEnabled, "Contextual meanings must require installed local resources.");
        model.ContextReady = true; model.Notify(); context.IsChecked = false;
        Check(context.IsEnabled && !ReaderPreferences.Load(preferenceFile).ContextualMeanings, "The installed offline contextual model must enable a persistent user toggle.");
        var bridgeLine = new BridgeLine(); var text = new[] { new BridgeToken("Danish", false), new BridgeToken("English", true, true) };
        bridgeLine.SetTokens(text); Layout(bridgeLine, 394, 100); var child = bridgeLine.Children[0]; bridgeLine.SetTokens(text);
        Check(bridgeLine.Updates == 1 && ReferenceEquals(child, bridgeLine.Children[0]), "Unchanged sentence content must reuse its existing layout nodes.");
        var tray = new TrayPanel(model); Layout(tray, 290, 500);
        Descendants<Button>(tray).First(b => b.Content is StackPanel).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Check(toggles == 1 && tray.ActualWidth == 290, "The real tray start card must invoke the app toggle at Mac popover width.");
        var popup = new TrayPopup(model); var popupSize = popup.MeasurePopup();
        var popupHandle = new WindowInteropHelper(popup).EnsureHandle();
        Check(Math.Abs(popupSize.Width - 326) <= 1 && popupSize.Height is > 300 and < 600 && !popup.IsVisible && (NativeMethods.GetWindowLongPtr(popupHandle, -20).ToInt64() & 0x80) != 0,
            $"The native tray popover must fit its content and shadow without appearing as a taskbar window. Size={popupSize}, visible={popup.IsVisible}, style={NativeMethods.GetWindowLongPtr(popupHandle, -20).ToInt64():x}."); popup.Close();
        var now = DateTimeOffset.Now; store.Save("æbler", "apples", "Jeg spiser æbler.", now.AddDays(-2));
        var book = new WordBookPanel(store, _ => spoken++, new ReaderPreferences()); Layout(book, 820, 500);
        Check(Descendants<ListBoxItem>(book).Count() == 1, "Book rows must render saved words.");
        book.BeginReview(); book.Reveal(); book.Answer(false); book.Reveal(); book.Answer(true); Layout(book, 820, 500);
        Check(book.ReviewSession?.Current is null && spoken == 2, "Same-window review must replay a missed word once and speak each card.");
        Descendants<Button>(book).Single(b => Equals(b.Content, "Back to Word Book")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); Layout(book, 820, 500);
        Check(book.ReviewSession is null && Descendants<ListBoxItem>(book).Count() == 1, "Finishing review must restore the same Word Book view.");
        book.BeginReview(); book.Reveal(); book.Answer(true); Layout(book, 820, 500);
        Check(book.ReviewSession?.Current is null, "A second review session must remain usable after returning to the book.");
        var source = new PixelRect(200, 200, 500, 60); var display = new PixelRect(0, 0, 1000, 700);
        foreach (bool sentenceOnly in new[] { false, true })
        {
            var frame = OverlayLayout.PlaceSingle(new(400, 210, 60, 20), source, new(sentenceOnly ? 420 : 280, 100), display, sentenceOnly);
            Check(frame is not null && !OverlayLayout.Intersects(frame.Value, source), "Either panel alone must avoid the full source block.");
        }
        using var overlay = new OverlayWindow();
        overlay.Present(new(new("æbler", new(200, 200, 60, 20)), new("æbler", [])), "apples", "", false, false, false, showWord: false, showSentence: false);
        Check(!overlay.IsVisible, "Speech-only mode must create no visible learning surface.");
    }
}
