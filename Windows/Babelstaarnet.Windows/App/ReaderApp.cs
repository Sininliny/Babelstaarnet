using Babelstaarnet.Core;
using Microsoft.Win32;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Threading;
using Forms = System.Windows.Forms;

namespace Babelstaarnet.Windows;

internal sealed class ReaderApp : Application
{
    private Forms.NotifyIcon? tray;
    private readonly BrandIcons icons = new();
    private readonly ArgosClient translator = new();
    private readonly SpeechService speech = new();
    private readonly ScreenReader screen = new();
    private readonly ContextualGlossClient contextual = new();
    private VocabularyStore vocabulary = null!;
    private ReaderUiModel model = null!;
    private HotKeyService? hotkeys;
    private OverlayWindow overlay = null!;
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromMilliseconds(35) };
    private HoverSession session = null!;
    private readonly ReaderPreferences preferences = ReaderPreferences.Load();
    private readonly LatencyLog timings = new(Path.Combine(AppPaths.DataDirectory, "performance.json"));
    private DateTimeOffset focusSettled, settledSince, lastScan;
    private bool cardTimed, meaningTimed, active, scanning, pinned, saveMeaningWhenReady, speechWarningShown;
    private bool warming, enginesReady, shuttingDown, idle;
    private readonly Dictionary<string, IReadOnlyList<RecognizedLine>> frozenPages = [];
    private bool lastFollow, lastWord, lastSentence, lastReadAloud;
    private double lastSpeechDelay;
    private int captureFailures;
    private PixelPoint? previous, lastScanPoint;
    private CancellationTokenSource? pending, delayedSpeech;
    private HoveredText? current => session.Current;
    private string currentMeaning => session.Meaning;
    private Window? settings;
    private WordBookWindow? book;
    private NewsService news = null!;
    private readonly DispatcherTimer newsTimer = new() { Interval = TimeSpan.FromMinutes(1) };
    private TrayPopup? popup;
    private TrayMenu? trayMenu;
    private NewsPopupWindow? newsPopup;
    private bool newsTickBusy;
    private Process? installer;
    private Task? initialization;

    [STAThread]
    public static int Main(string[] arguments)
    {
        if (arguments.Contains("--check"))
        {
            try
            {
                if (SharedPolicy.bp_version() != 1 || SharedPolicy.bp_reading_help(1, 0, 1, 0) != 1) return 4;
                _ = ScreenReader.DanishAvailable; _ = BrandIcons.AppImage;
                using var brand = new BrandIcons(); _ = brand.Tray(false); _ = brand.Tray(true);
                if (!File.Exists(AppPaths.Bridge) || !File.Exists(AppPaths.Installer) || !File.Exists(AppPaths.SpeechBridge) || !File.Exists(AppPaths.SpeechInstaller)) return 2;
                using var surfaces = new OverlayWindow(); return surfaces.CheckNativeSurfaces() ? 0 : 3;
            }
            catch { return 1; }
        }
        using var mutex = new Mutex(true, @"Local\Babelstaarnet.Windows", out bool first);
        if (!first) { Ui.Error("Babelstårnet is already running. Look for its tower icon in the system tray."); return 0; }
        try { return new ReaderApp().Run(); }
        catch (Exception error) { Ui.Error(error.Message); return 1; }
    }

    protected override void OnStartup(StartupEventArgs e)
    {
        WindowsTheme.Current.Apply(preferences.Appearance);
        base.OnStartup(e); ShutdownMode = ShutdownMode.OnExplicitShutdown;
        if (preferences.SpeechEngine == "windows") speech.SelectEngine(new WindowsDanishEngine());
        vocabulary = new VocabularyStore(Path.Combine(AppPaths.DataDirectory, "vocabulary.json"));
        news = new NewsService(AppPaths.DataDirectory) { LearningUnits = () => vocabulary.RecentLearningUnits(DateTimeOffset.Now) };
        news.ReadingActive = () => active && !idle;
        news.Reader.Translate = async (texts, token) =>
        {
            if (!translator.IsInstalled) throw new InvalidOperationException("Install local translation in Settings → Local engines first.");
            return await translator.TranslateAsync(texts, token);
        };
        news.Reader.CachedWordMeaning = word => vocabulary.SavedMeaning(word) ?? (ReadingPolicy.TryGloss(ReadingPolicy.Glosses, word, out var gloss) ? gloss : null);
        news.Reader.KnowledgeLevel = vocabulary.EffectiveLevel;
        news.Reader.Speak = text => Speak(text);
        news.Reader.SaveWord = (word, meaning, context) => { vocabulary.Save(word, meaning, context, DateTimeOffset.Now); };

        news.MeaningPreservationWords = DanishLanguage.Shared.MeaningPreservationWords;
        news.LanguageInstructions = DanishLanguage.Shared.NewsSimplificationInstructions;
        news.SimplifyExcerpt = contextual.SimplifyPublicExcerptAsync; news.ModelAvailable = () => contextual.IsInstalled; news.ModelIdentity = () => contextual.ModelIdentity;
        model = new ReaderUiModel(preferences, vocabulary)
        {
            Toggle = Toggle, OpenSettings = ShowSettings, OpenBook = () => { ShowBook(); book?.OpenWords(); },
            OpenNews = () => { ShowBook(); book?.OpenNews(); }, OpenNewsSettings = () => { ShowSettings(); if (settings?.Content is SettingsShell shell) shell.SelectPage("News (internet)"); }, OpenReadingControls = ShowTray, Quit = Shutdown, Apply = ApplyPreferences,
            SelectVoice = SelectVoice, InstallTranslation = () => StartInstall(false), InstallVoice = () => StartInstall(true),
            CheckEngines = CheckEngines, TryVoice = () => Speak("Jeg spiser æbler. Det er en anspændt situation, men vi finder en løsning."),
            OpenLanguageSettings = () => Process.Start(new ProcessStartInfo("ms-settings:regionlanguage") { UseShellExecute = true }),
            ExportProfile = ExportProfile, ImportProfile = ImportProfile, ResetProfile = ResetProfile,
            InstallContext = InstallContext, CheckContext = () => _ = WarmContextAsync(),
            GetContextRuntime = () => Process.Start(new ProcessStartInfo("https://ollama.com/download/windows") { UseShellExecute = true }),
            ChangeShortcuts = ChangeShortcuts, ShortcutCapture = value => { try { hotkeys?.Suspend(value); } catch (Exception error) { model.ShortcutMessage = error.Message; model.Notify(); } }
        };
        model.News = news;
        vocabulary.Changed += () => { session?.InvalidateProjection(); if (popup?.IsVisible == true || settings?.IsVisible == true) UpdateTray(); };
        session = new HoverSession(word => translator.TryGetCached(word, out var meaning) ? meaning : null, translator.TranslateAsync, vocabulary.IsKnown);
        session.LearnedBefore = vocabulary.LearningCandidate;
        session.PreviousMeaning = vocabulary.SavedMeaning;
        session.KnowledgeLevel = vocabulary.EffectiveLevel;
        session.LemmaFound += (word, lemma) => vocabulary.RecordLemma(word, lemma);
        session.ContextFailed += error => { model.ContextMessage = error.Message; if (contextual.HasFailed) session.ContextProvider = null; model.Notify(); };
        contextual.Changed += () => Dispatcher.BeginInvoke(new Action(() => { if (!shuttingDown) { model.ContextMessage = contextual.LastFailure; UpdateTray(); } }));
        session.Changed += Present; session.ReadAloud += ScheduleSpeech; session.Failed += ReadingFailed;
        overlay = new OverlayWindow(); overlay.Known += () => Feedback(true); overlay.Unknown += () => Feedback(false); overlay.Pin += TogglePin;
        overlay.SentenceMeaningRequested += () => _ = session.ToggleSentenceMeaningAsync();
        overlay.Listen += () => { if (current is not null) Speak(current.Word.Text); };
        tray = new Forms.NotifyIcon { Text = "Babelstårnet · inactive", Icon = icons.Tray(false), Visible = true };
        trayMenu = new TrayMenu(model); tray.ContextMenuStrip = trayMenu;
        tray.MouseClick += (_, mouse) => { if (mouse.Button == Forms.MouseButtons.Left) Ui.Try(() => trayMenu.Show(Forms.Cursor.Position)); };
        news.PopupAllowed = () => !shuttingDown && NotificationsAccepted();
        news.PresentPopup = item =>
        {
            if (newsPopup is not null || !news.PopupAllowed()) return false;
            NewsPopupWindow? next = null;
            try {
                next = new NewsPopupWindow(news, item, () => { ShowBook(); book?.OpenNews(); }); newsPopup = next;
                next.Closed += (_, _) => { if (ReferenceEquals(newsPopup, next)) newsPopup = null; }; next.ShowCard(); return true;
            } catch (Exception error) {
                next?.Close(); newsPopup = null;
                if (Ui.ErrorRaised is { } report) report(error);
                model.DataMessage = "News card could not open: " + error.Message; model.Notify(); return false;
            }
        };
        tray.BalloonTipClicked += (_, _) => Ui.Try(() => { ShowBook(); book?.OpenNews(); });
        newsTimer.Tick += async (_, _) =>
        {
            if (newsTickBusy) return;
            newsTickBusy = true;
            try {
            await news.RefreshAsync(background: true);
            await news.TickPopupAsync();
            if (news.DigestDue(active, NotificationsAccepted()) && news.DigestCandidates.Count > 0)
            { tray.ShowBalloonTip(7000, "DR · something new to read", news.DigestCandidates[0].Title, Forms.ToolTipIcon.Info); news.DigestSent(); }
            } finally { newsTickBusy = false; }
        };
        news.Changed += () => { newsTimer.IsEnabled = news.Preferences.Enabled && news.Preferences.Background; model.Notify(); };
        newsTimer.IsEnabled = news.Preferences.Enabled && news.Preferences.Background;
        SystemEvents.UserPreferenceChanged += ThemeChanged;
        try
        {
            hotkeys = new HotKeyService();
            hotkeys.Pressed += id => Ui.Try(() => { switch (id) { case 1: Toggle(); break; case 2: Feedback(true); break; case 3: Feedback(false); break; case 4: TogglePin(); break; case 5: _ = session.ToggleSentenceMeaningAsync(); break; } });
            hotkeys.Configure(preferences.Shortcuts);
        }
        catch (Exception error) { model.ShortcutMessage = error.Message + " Use the tray menu or choose another shortcut in Settings."; }
        lastFollow = preferences.FollowScreenChanges; lastWord = preferences.WordMeaning; lastSentence = preferences.WholeSentence;
        lastReadAloud = preferences.ReadAloud; lastSpeechDelay = preferences.SpeakAfterSeconds;
        ApplyPreferences(); UpdateTray(); timer.Tick += async (_, _) => await ScanAsync();
        if (!translator.IsInstalled || !ScreenReader.DanishAvailable || preferences.ReadAloud && !speech.IsAvailable) ShowSettings();
        else PrepareEngines();
    }
    private void ThemeChanged(object sender, UserPreferenceChangedEventArgs e) => Dispatcher.BeginInvoke(new Action(() => { if (!shuttingDown) { RefreshTheme(); UpdateTray(); } }));
    private void RefreshTheme()
    {
        WindowsTheme.Current.Apply(preferences.Appearance);
        foreach (Window window in Windows) WindowsTheme.Current.ApplyNative(window);
    }
    private void ShowTray()
    {
        if (popup is not null) { DismissTray(); return; }
        ClearBubble(); var next = new TrayPopup(model); popup = next;
        next.Closed += (_, _) => { if (ReferenceEquals(popup, next)) popup = null; }; next.OpenAtCursor();
    }
    private void DismissTray()
    { var previousPopup = popup; popup = null; previousPopup?.Dismiss(); }
    private void Toggle()
    {
        if (model.Installing) return;
        if (!active && (!translator.IsInstalled || !ScreenReader.DanishAvailable)) { ShowSettings(); return; }
        active = !active; model.Failure = null; CancelPending(); ClearBubble(); previous = lastScanPoint = null; frozenPages.Clear(); idle = false; captureFailures = 0;
        session.ResetLearningSession();
        if (active) news.CancelGeneration();
        timer.Interval = TimeSpan.FromMilliseconds(35); timer.IsEnabled = active;
        if (active) { contextual.ResetFailure(); ApplyPreferences(); }
        if (active) PrepareEngines(); UpdateTray();
    }
    private void UpdateTray()
    {
        if (shuttingDown) return;
        model.Active = active; model.Busy = warming; model.Idle = idle; model.Installing = installer is not null;
        model.OcrReady = ScreenReader.DanishAvailable; model.TranslationReady = translator.IsInstalled; model.VoiceReady = speech.IsAvailable; model.VoiceName = speech.EngineName;
        model.ContextReady = contextual.IsInstalled; model.ContextRuntimeReady = contextual.RuntimeAvailable;
        if (tray is not null) { tray.Text = "Babelstårnet · " + (warming ? "preparing local engines" : idle ? "idle" : active ? "active" : "inactive"); tray.Icon = icons.Tray(active); }
        model.Notify();
    }
    private void ApplyPreferences()
    {
        RefreshTheme();
        bool panelsChanged = lastWord != preferences.WordMeaning || lastSentence != preferences.WholeSentence;
        if (lastFollow != preferences.FollowScreenChanges) { CancelPending(); frozenPages.Clear(); lastScanPoint = null; lastScan = default; }
        if (lastReadAloud != preferences.ReadAloud || lastSpeechDelay != preferences.SpeakAfterSeconds) CancelSpeech();
        lastFollow = preferences.FollowScreenChanges; lastWord = preferences.WordMeaning; lastSentence = preferences.WholeSentence;
        lastReadAloud = preferences.ReadAloud; lastSpeechDelay = preferences.SpeakAfterSeconds;
        session.TranslateMeaning = preferences.WordMeaning; session.TranslateSentence = preferences.WholeSentence;
        session.SupportedReading = preferences.SupportedReading; session.InvalidateProjection();
        session.ContextProvider = preferences.ContextualMeanings && contextual.IsInstalled && !contextual.HasFailed ? (hit, token, ready) => contextual.ExplainAsync(hit, token, ready, preferences.WholeSentence, vocabulary.IsKnown) : null;
        if (panelsChanged && current is { } hit) { session.Clear(); _ = session.FocusAsync(hit); }
        if (current is not null) Present(); else overlay.Hide();
        UpdateTray();
    }
    private string? ChangeShortcuts(HotKeyConfiguration next)
    {
        if (next.ValidationError() is { } invalid) return invalid;
        try { hotkeys?.Configure(next); preferences.Shortcuts = next; preferences.Save(); model.ShortcutMessage = null; UpdateTray(); return null; }
        catch (Exception error) { return error.Message; }
    }
    private void PrepareEngines()
    {
        if (enginesReady || initialization is { IsCompleted: false }) return;
        warming = true; UpdateTray(); initialization = InitializeEnginesAsync();
        if (preferences.ContextualMeanings) _ = WarmContextAsync();
    }
    private async Task WarmContextAsync()
    {
        if (model.ContextBusy || !contextual.IsInstalled) return;
        model.ContextBusy = true; model.Notify();
        try { contextual.ResetFailure(); await contextual.WarmAsync(CancellationToken.None); model.ContextMessage = "Local contextual meanings are ready."; ApplyPreferences(); }
        catch (Exception error) { if (!shuttingDown) model.ContextMessage = error.Message; }
        finally { model.ContextBusy = false; if (!shuttingDown) UpdateTray(); }
    }
    private async void InstallContext()
    {
        if (model.ContextBusy) return;
        model.ContextBusy = true; model.ContextMessage = null; model.Notify();
        try { await contextual.InstallAsync(CancellationToken.None); model.ContextMessage = "The offline contextual model is installed."; ApplyPreferences(); }
        catch (Exception error) { if (!shuttingDown) model.ContextMessage = error.Message; }
        finally { model.ContextBusy = false; if (!shuttingDown) UpdateTray(); }
    }
    private async Task InitializeEnginesAsync()
    {
        try
        {
            _ = WarmSpeechAsync();
            await Task.WhenAll(Task.Run(() => translator.WarmAsync(CancellationToken.None)), Task.Run(screen.WarmAsync)); enginesReady = true; model.Failure = null;
        }
        catch (Exception error) { if (!shuttingDown) ReadingFailed(error); }
        finally { warming = false; if (!shuttingDown) UpdateTray(); }
    }
    private async void CheckEngines()
    {
        if (warming || model.Installing) return;
        warming = true; UpdateTray();
        try
        {
            if (!ScreenReader.DanishAvailable) throw new InvalidOperationException("Install Danish optical character recognition in Windows language settings.");
            await translator.WarmAsync(CancellationToken.None); await speech.WarmAsync(); enginesReady = true; model.Failure = null;
        }
        catch (Exception error) { model.Failure = error.Message; }
        finally { warming = false; UpdateTray(); }
    }
    private void CancelPending() => pending?.Cancel();
    private void CancelSpeech() { delayedSpeech?.Cancel(); delayedSpeech = null; speech.Stop(); }
    private void ClearBubble()
    {
        pinned = false; saveMeaningWhenReady = false; session.Clear(); CancelSpeech(); overlay.Hide(); hotkeys?.EnableFeedback(false);
    }
    private bool Holding => preferences.Shortcuts.HoldModifier switch
    {
        HoldModifier.Control => Down(0x11), HoldModifier.Shift => Down(0x10), HoldModifier.Windows => Down(0x5B) || Down(0x5C), _ => Down(0x12)
    };
    private static bool Down(int key) => (NativeMethods.GetAsyncKeyState(key) & 0x8000) != 0;
    private async Task ScanAsync()
    {
        if (!active) return;
        bool shouldIdle = preferences.FollowScreenChanges && preferences.PowerSaving && NativeMethods.InputIdle >= TimeSpan.FromSeconds(5);
        timer.Interval = shouldIdle ? TimeSpan.FromMilliseconds(250) : TimeSpan.FromMilliseconds(35);
        if (idle != shouldIdle) { idle = shouldIdle; if (!idle) { news.CancelGeneration(); lastScanPoint = null; lastScan = default; } UpdateTray(); }
        if (idle || pinned || Holding || NativeMethods.IsOwnForegroundWindow() || !NativeMethods.GetCursorPos(out var position)) return;
        var pointer = new PixelPoint(position.X, position.Y); if (overlay.Contains(pointer)) return;
        var now = DateTimeOffset.UtcNow;
        if (previous is not { } oldPointer || HoverScanPolicy.Moved(pointer, oldPointer))
        {
            previous = pointer; settledSince = now;
            if (current is null || !current.Word.Bounds.Contains(pointer, 3)) { CancelPending(); ClearBubble(); } return;
        }
        if (scanning || !HoverScanPolicy.ShouldScan(pointer, lastScanPoint, settledSince, lastScan, now, current is not null)) return;
        scanning = true; lastScan = now; lastScanPoint = pointer;
        using var request = new CancellationTokenSource(); pending = request;
        try
        {
            var watch = Stopwatch.StartNew(); int snapshots = screen.SnapshotHits;
            var display = Forms.Screen.FromPoint(new System.Drawing.Point(pointer.X, pointer.Y));
            string displayKey = display.DeviceName + display.Bounds;
            bool frozen = !preferences.FollowScreenChanges && frozenPages.ContainsKey(displayKey);
            IReadOnlyList<RecognizedLine> lines = frozen ? frozenPages[displayKey] : await screen.ReadAsync(pointer, request.Token, overlay.CaptureWithoutOverlayAsync, !preferences.FollowScreenChanges);
            request.Token.ThrowIfCancellationRequested();
            if (!preferences.FollowScreenChanges && !frozen) frozenPages[displayKey] = lines;
            captureFailures = 0;
            if (!frozen) timings.Record(screen.SnapshotHits > snapshots ? "verified_snapshot" : "capture_ocr", watch.Elapsed.TotalMilliseconds);
            request.Token.ThrowIfCancellationRequested(); if (!active || !NativeMethods.GetCursorPos(out var latest)) return;
            var hit = ReadingPolicy.HitTest(lines, new(latest.X, latest.Y)); if (hit is null) { ClearBubble(); return; }
            hit = SentenceWindow.Around(ReadingContext.Assemble(hit, lines));
            if (current?.Word != hit.Word || current.Line.Text != hit.Line.Text || current.FocusOccurrence != hit.FocusOccurrence)
            {
                focusSettled = settledSince; cardTimed = meaningTimed = false; _ = session.FocusAsync(hit);
                _ = Dispatcher.BeginInvoke(DispatcherPriority.Background, new Action(() => Ui.Try(() => vocabulary.Observe(hit.Word.Text, hit.Line.Text, DateTimeOffset.Now))));
            }
        }
        catch (OperationCanceledException) { }
        catch (Exception error) { if (++captureFailures >= 5) ReadingFailed(error); }
        finally { if (ReferenceEquals(pending, request)) pending = null; scanning = false; }
    }
    private void ReadingFailed(Exception error)
    {
        active = false; timer.Stop(); enginesReady = false; CancelPending(); ClearBubble(); model.Failure = error.Message; UpdateTray();
        tray?.ShowBalloonTip(6000, "Babelstårnet · reading paused", error.Message, Forms.ToolTipIcon.Warning);
    }
    private void Present()
    {
        if (current is null) return;
        if (!active || !pinned && !Holding && (!NativeMethods.GetCursorPos(out var pointer) || !current.Word.Bounds.Contains(new(pointer.X, pointer.Y), 3))) { ClearBubble(); return; }
        overlay.Present(current, currentMeaning, "", pinned, session.Loading, !session.NewSense && vocabulary.IsKnown(ReadingPolicy.Key(current.Word.Text)), session.Tokens,
            preferences.WordMeaning, preferences.WholeSentence, preferences.Shortcuts, vocabulary.EffectiveLevel(current.Word.Text), session.ExplanationTokens, session.SentenceMeaning, session.SentenceHelp, session.MeaningStatus);
        if (saveMeaningWhenReady && !session.Loading) { saveMeaningWhenReady = false; vocabulary.Save(current.Word.Text, currentMeaning, current.Line.Text, DateTimeOffset.Now); }
        if (!cardTimed) { cardTimed = true; timings.Record("pointer_settled_to_card", (DateTimeOffset.UtcNow - focusSettled).TotalMilliseconds); }
        if (!session.Loading && !meaningTimed) { meaningTimed = true; timings.Record("pointer_settled_to_meaning", (DateTimeOffset.UtcNow - focusSettled).TotalMilliseconds); }
        try { hotkeys?.EnableFeedback(overlay.IsVisible); } catch (System.ComponentModel.Win32Exception error) { model.ShortcutMessage = error.Message; }
    }
    private void Feedback(bool known)
    {
        if (current is null) return;
        var now = DateTimeOffset.Now;
        if (!known) { vocabulary.Save(current.Word.Text, currentMeaning, current.Line.Text, now); saveMeaningWhenReady = session.Loading; }
        vocabulary.Mark(current.Word.Text, known, now); session.Refresh(); overlay.SetFeedback(known); Present();
    }
    private async void ScheduleSpeech(string word)
    {
        CancelSpeech(); if (!preferences.ReadAloud) return;
        using var request = new CancellationTokenSource(); delayedSpeech = request;
        try
        {
            // Delay only speech; slow OCR must not impose a second full dwell.
            double remaining = Math.Max(0, preferences.SpeakAfterSeconds * 1000 - (DateTimeOffset.UtcNow - focusSettled).TotalMilliseconds);
            await Task.Delay(TimeSpan.FromMilliseconds(remaining), request.Token); request.Token.ThrowIfCancellationRequested();
            if (active && current is not null && ReadingPolicy.Key(current.Word.Text) == ReadingPolicy.Key(word)) Speak(word, automatic: true);
        }
        catch (OperationCanceledException) { }
        finally { if (ReferenceEquals(delayedSpeech, request)) delayedSpeech = null; }
    }
    private async Task WarmSpeechAsync()
    { try { await speech.WarmAsync(); } catch { } finally { if (!shuttingDown) UpdateTray(); } }
    private async void Speak(string word, bool automatic = false)
    {
        if (!automatic) { delayedSpeech?.Cancel(); delayedSpeech = null; }
        try { var watch = Stopwatch.StartNew(); await speech.SpeakAsync(word); if (automatic) timings.Record("voice_start", watch.Elapsed.TotalMilliseconds); }
        catch (Exception error)
        {
            if (shuttingDown) return;
            if (!automatic) Ui.Error(error.Message);
            else if (!speechWarningShown) { speechWarningShown = true; tray?.ShowBalloonTip(5000, "Babelstårnet · Danish voice", error.Message, Forms.ToolTipIcon.Info); }
        }
    }
    private void TogglePin()
    {
        if (current is null) return;
        if (!pinned) { vocabulary.Save(current.Word.Text, currentMeaning, current.Line.Text, DateTimeOffset.Now); saveMeaningWhenReady = session.Loading; }
        pinned = !pinned; Present();
    }
    private void ShowSettings()
    {
        DismissTray(); ClearBubble();
        if (settings is not null) { settings.Activate(); return; }
        settings = CreateSettingsWindow(model);
        settings.Closed += (_, _) => settings = null; settings.Show();
    }
    internal static Window CreateSettingsWindow(ReaderUiModel model)
    {
        var window = new Window { Title = "Babelstårnet · Settings", Icon = BrandIcons.AppImage, Width = 880, Height = Math.Min(720, SystemParameters.WorkArea.Height - 48), MinWidth = 720, MinHeight = 420, WindowStartupLocation = WindowStartupLocation.CenterScreen, Content = new SettingsShell(model) };
        WindowsTheme.Current.Attach(window); return window;
    }
    private void ShowBook()
    {
        DismissTray(); ClearBubble();
        if (book is not null) { book.Activate(); return; }
        book = new WordBookWindow(vocabulary, word => Speak(word), preferences, FillMissingMeanings, news, () => { ShowSettings(); if (settings?.Content is SettingsShell shell) shell.SelectPage("News (internet)"); }); book.Closed += (_, _) => book = null; book.Show();
    }
    private async void FillMissingMeanings()
    {
        if (!translator.IsInstalled) return;
        try
        {
            foreach (var entry in vocabulary.Saved.Where(e => e.Meaning.Length == 0).ToArray())
            {
                if (book is null || shuttingDown) break;
                var translated = await translator.TranslateAsync([entry.Word], CancellationToken.None); vocabulary.SetMeaning(entry.Key, translated[0]);
            }
        }
        catch (Exception error) { model.DataMessage = "Some saved meanings could not be filled: " + error.Message; model.Notify(); }
    }
    private void SelectVoice(string choice)
    {
        ISpeechEngine next = choice == "windows" ? new WindowsDanishEngine() : new NeuralSpeechEngine();
        if (!next.IsAvailable) { next.Dispose(); model.Failure = choice == "piper" ? "Install the offline Danish neural voice first." : "Install a Danish Windows speech voice in Language settings first."; UpdateTray(); return; }
        CancelSpeech(); speech.SelectEngine(next); speechWarningShown = false; preferences.SpeechEngine = choice; preferences.Save(); _ = WarmSpeechAsync(); UpdateTray();
    }
    private void ExportProfile()
    {
        var dialog = new SaveFileDialog { FileName = "Babelstaarnet-profile.json", Filter = "Learning profiles|*.json" };
        if (dialog.ShowDialog(settings) != true) return;
        File.WriteAllText(dialog.FileName, vocabulary.ExportProfile(DateTimeOffset.Now), new UTF8Encoding(false)); model.DataMessage = "Learning profile exported."; model.Notify();
    }
    private void ImportProfile()
    {
        var dialog = new OpenFileDialog { Filter = "Learning profiles|*.json" };
        if (dialog.ShowDialog(settings) != true) return;
        try
        {
            if (new FileInfo(dialog.FileName).Length > 25_000_000) throw new InvalidDataException("This learning profile is too large to import.");
            int count = vocabulary.ImportProfile(File.ReadAllText(dialog.FileName), DateTimeOffset.Now); model.DataMessage = $"Merged {count} word records without double-counting."; session.Refresh();
        }
        catch (Exception error) { model.DataMessage = "Could not import this profile: " + error.Message; }
        model.Notify();
    }
    private void ResetProfile()
    {
        if (MessageBox.Show(settings!, "Reset the words Babelstårnet has learned about you? Your Word Book will be kept.", "Reset learning", MessageBoxButton.OKCancel, MessageBoxImage.Question) != MessageBoxResult.OK) return;
        vocabulary.ResetLearning(); model.DataMessage = "Learning progress reset. Your Word Book has been kept."; session.Refresh(); model.Notify();
    }
    private void StartInstall(bool voice)
    {
        if (installer is not null) return;
        active = false; timer.Stop(); CancelPending(); ClearBubble();
        var start = new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe"))
        { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true };
        foreach (string argument in new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", voice ? AppPaths.SpeechInstaller : AppPaths.Installer, "-DataDirectory", AppPaths.DataDirectory }) start.ArgumentList.Add(argument);
        installer = Process.Start(start) ?? throw new IOException("Could not start offline setup."); model.Failure = null; UpdateTray(); _ = FinishInstallAsync(installer, voice);
    }
    private async Task FinishInstallAsync(Process process, bool voice)
    {
        Task<string> output = process.StandardOutput.ReadToEndAsync(), errors = process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync(); await output; string details = await errors; bool success = process.ExitCode == 0; process.Dispose(); installer = null;
        if (shuttingDown) return;
        if (success) { if (voice) SelectVoice("piper"); else { enginesReady = false; PrepareEngines(); } model.Failure = null; model.DataMessage = voice ? "The offline Danish neural voice is ready." : "Offline translation is ready."; }
        else model.Failure = "Setup failed. " + details[^Math.Min(details.Length, 1800)..];
        UpdateTray();
    }
    protected override void OnExit(ExitEventArgs e)
    {
        shuttingDown = true; timer.Stop(); newsTimer.Stop(); newsPopup?.Close(); trayMenu?.Dispose(); news.Dispose(); CancelPending(); CancelSpeech(); SystemEvents.UserPreferenceChanged -= ThemeChanged;
        hotkeys?.Dispose(); session.Dispose(); overlay.Dispose(); translator.Dispose(); speech.Dispose(); contextual.Dispose(); vocabulary.Flush();
        if (tray is not null) { tray.Visible = false; tray.Dispose(); } icons.Dispose(); base.OnExit(e);
    }
    [System.Runtime.InteropServices.DllImport("shell32.dll")]
    private static extern int SHQueryUserNotificationState(out int state);
    private static bool NotificationsAccepted() => SHQueryUserNotificationState(out int state) == 0 && state == 5;
}
