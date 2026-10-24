using Babelstaarnet.Core;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace Babelstaarnet.Windows;

internal sealed class SettingsPanel : ScrollViewer
{
    private readonly ReaderUiModel model;
    private readonly List<Action> refresh = [];
    private readonly StackPanel form = new() { Margin = new Thickness(20, 16, 20, 24) };
    private bool refreshing;
    private readonly Dictionary<string, FrameworkElement[]> sections = [];
    public void ShowSection(string name)
    {
        foreach (var section in sections) { section.Value[0].Visibility = Visibility.Collapsed; section.Value[1].Visibility = section.Key == name ? Visibility.Visible : Visibility.Collapsed; }
        ScrollToTop();
    }
    public SettingsPanel(ReaderUiModel model)
    {
        this.model = model; Width = 480; Background = Ui.Paper; VerticalScrollBarVisibility = ScrollBarVisibility.Auto; HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled;
        Content = form;
        var translation = Section("Translation");
        Toggle(translation, "Word meaning", () => model.Preferences.WordMeaning, v => model.Preferences.WordMeaning = v);
        Toggle(translation, "Whole sentence", () => model.Preferences.WholeSentence, v => model.Preferences.WholeSentence = v);
        Caption(translation, "Hovering a Danish word shows what it means. Use either panel on its own or both together; turning both off keeps Danish speech on hover.");
        Toggle(translation, "Speak Danish on hover", () => model.Preferences.ReadAloud, v => model.Preferences.ReadAloud = v);
        var voices = new ComboBox { Width = 216, FontSize = 12, ItemsSource = new[] { "Danish neural · offline", "Windows Danish · basic" } };
        FormControls.Apply(voices);
        voices.SelectedIndex = model.Preferences.SpeechEngine == "windows" ? 1 : 0;
        voices.SelectionChanged += (_, _) => { if (!refreshing) model.SelectVoice(voices.SelectedIndex == 1 ? "windows" : "piper"); };
        Row(translation, "Voice", voices);
        refresh.Add(() => voices.SelectedIndex = model.Preferences.SpeechEngine == "windows" ? 1 : 0);
        Value(translation, "Current voice", () => model.VoiceName + (model.VoiceReady ? "" : " · not installed"));
        var voiceActions = new WrapPanel();
        voiceActions.Children.Add(Button("Try voice", model.TryVoice)); voiceActions.Children.Add(Button("Install neural voice", model.InstallVoice)); translation.Children.Add(voiceActions);
        var delay = new Slider { Minimum = .2, Maximum = 1.2, TickFrequency = .05, IsSnapToTickEnabled = true, Width = 170, Value = model.Preferences.SpeakAfterSeconds, VerticalAlignment = VerticalAlignment.Center };
        FormControls.Apply(delay);
        var delayText = Ui.Text("", 11); delayText.Margin = new Thickness(10, 0, 0, 0); delayText.Width = 42; delayText.TextAlignment = TextAlignment.Right;
        var delayRow = new StackPanel { Orientation = Orientation.Horizontal }; delayRow.Children.Add(delay); delayRow.Children.Add(delayText); Row(translation, "Speak after", delayRow);
        delay.ValueChanged += (_, _) => { if (refreshing) return; model.Preferences.SpeakAfterSeconds = delay.Value; model.Commit(); };
        refresh.Add(() => { delay.IsEnabled = model.Preferences.ReadAloud; delay.Value = model.Preferences.SpeakAfterSeconds; delayText.Text = delay.Value.ToString("0.00") + " s"; });
        Caption(translation, "How long the pointer rests on a word before it is spoken. The bubble itself appears as soon as the word is read.");

        var reading = Section("Reading");
        Toggle(reading, "Supported reading · more English anchors", () => model.Preferences.SupportedReading, v => model.Preferences.SupportedReading = v);
        Toggle(reading, "Follow screen changes", () => model.Preferences.FollowScreenChanges, v => model.Preferences.FollowScreenChanges = v);
        Toggle(reading, "Pause screen reading when idle", () => model.Preferences.PowerSaving, v => model.Preferences.PowerSaving = v, () => model.Preferences.FollowScreenChanges);
        Caption(reading, "Screen capture and OCR back off while the pointer is still, stop while a bubble is held, and pause after 5 seconds without input.");

        var newsSection = Section("News (internet)");
        Caption(newsSection, NewsService.Disclosure);
        if (model.News is { } news)
        {
            void Set(bool enabled, bool background, bool notify) => news.Configure(enabled, background, notify, news.Preferences.Topic, news.Preferences.DigestHour);
            Toggle(newsSection, "News recommendations (internet)", () => news.Preferences.Enabled, v => Set(v, news.Preferences.Background, news.Preferences.Notify));
            Toggle(newsSection, "Background refresh", () => news.Preferences.Background, v => Set(news.Preferences.Enabled, v, news.Preferences.Notify), () => news.Preferences.Enabled);
            Toggle(newsSection, "Scheduled adapted news cards", () => news.PopupPreferences.Enabled, v => news.ConfigurePopups(v, news.PopupPreferences.IntervalMinutes), () => news.Preferences.Enabled && news.Preferences.Background);
            var intervals = new[] { 60, 120, 240 };
            var cadence = new ComboBox { Width = 140, ItemsSource = new[] { "1 hour", "2 hours", "4 hours" }, SelectedIndex = Array.IndexOf(intervals, news.PopupPreferences.IntervalMinutes) }; FormControls.Apply(cadence);
            cadence.SelectionChanged += (_, _) => { if (!refreshing && cadence.SelectedIndex >= 0) news.ConfigurePopups(news.PopupPreferences.Enabled, intervals[cadence.SelectedIndex]); };
            Row(newsSection, "Show a card every", cadence); refresh.Add(() => cadence.SelectedIndex = Array.IndexOf(intervals, news.PopupPreferences.IntervalMinutes));
            Caption(newsSection, "While the app runs · 09:00–21:00 · at most 3 cards a day. No catch-up queue, sound or focus stealing. Reading takes priority. Enable background refresh above to schedule cards.");
            Caption(newsSection, "Each card uses installed local AI to simplify DR text, with Danish word hints. No local AI means no scheduled cards; the original remains in Word Book.");
            var popupActions = new WrapPanel(); popupActions.Children.Add(Button("Try a card now", () => _ = TryCard()));
            async System.Threading.Tasks.Task TryCard() { await news.RefreshAsync(true); await news.TickPopupAsync(preview: true); }
            var resume = Button("Resume news cards", () => news.PausePopupsForToday(false)); popupActions.Children.Add(resume); refresh.Add(() => resume.Visibility = news.PopupsPaused ? Visibility.Visible : Visibility.Collapsed); newsSection.Children.Add(popupActions);
            var popupStatus = Ui.Text("", 11); popupStatus.Foreground = Ui.Muted; newsSection.Children.Add(popupStatus); refresh.Add(() => popupStatus.Text = news.PopupsPaused ? "News cards are paused for today." : news.PopupStatus);
            Toggle(newsSection, "Daily headline notification · alternative to cards", () => news.Preferences.Notify, v => Set(news.Preferences.Enabled, news.Preferences.Background, v), () => news.Preferences.Enabled && news.Preferences.Background);
            var hour = new ComboBox { Width = 140, ItemsSource = Enumerable.Range(9, 12).Select(h => h.ToString("00") + ":00").ToArray(), SelectedIndex = news.Preferences.DigestHour - 9 };
            FormControls.Apply(hour); hour.SelectionChanged += (_, _) => { if (hour.SelectedIndex >= 0) news.Configure(news.Preferences.Enabled, news.Preferences.Background, news.Preferences.Notify, news.Preferences.Topic, hour.SelectedIndex + 9); }; Row(newsSection, "Digest time", hour);
            Caption(newsSection, "Enabling this notification turns scheduled cards off. At most one daily digest. Quiet hours 21:00–09:00; no notification while reading. Turning news off also turns background refresh and notifications off.");
        }
        var shortcuts = Section("Shortcuts");
        foreach (var action in Enum.GetValues<ShortcutAction>())
        { var recorder = new ShortcutRecorder(model, action); Row(shortcuts, HotKeyConfiguration.Title(action), recorder); refresh.Add(recorder.Refresh); }
        var hold = new ComboBox { Width = 145, ItemsSource = Enum.GetValues<HoldModifier>(), SelectedItem = model.Preferences.Shortcuts.HoldModifier };
        FormControls.Apply(hold);
        hold.SelectionChanged += (_, _) => { if (!refreshing && hold.SelectedItem is HoldModifier modifier) { model.ShortcutMessage = model.ChangeShortcuts(model.Preferences.Shortcuts with { HoldModifier = modifier }); model.Notify(); } };
        Row(shortcuts, "Hold bubble", hold); refresh.Add(() => hold.SelectedItem = model.Preferences.Shortcuts.HoldModifier);
        Caption(shortcuts, "Click a shortcut, then press its replacement. Bubble shortcuts are active only while a learning bubble is visible.");
        var shortcutMessage = Caption(shortcuts, ""); refresh.Add(() => { shortcutMessage.Text = model.ShortcutMessage ?? ""; shortcutMessage.Visibility = string.IsNullOrWhiteSpace(model.ShortcutMessage) ? Visibility.Collapsed : Visibility.Visible; });
        shortcuts.Children.Add(Button("Restore Default Shortcuts", () => { model.ShortcutMessage = model.ChangeShortcuts(HotKeyConfiguration.Defaults) ?? "Shortcuts restored to defaults."; model.Notify(); }));

        var learning = Section("What you have picked up");
        Value(learning, "Danish words seen", () => Words(model.Vocabulary.TrackedCount)); Value(learning, "Probably understood", () => Words(model.Vocabulary.FamiliarCount));
        Caption(learning, "Babelstårnet keeps track of which Danish words keep coming back to you and quietly shows less English for those. Reading is enough to move it. Knew and Don’t know correct it when needed. Stored only on this PC; imports merge without double-counting.");
        Value(learning, "In your word book", () => Words(model.Vocabulary.Saved.Count()) + (model.DueCount > 0 ? $", {model.DueCount} to review" : ""));
        var dataActions = new WrapPanel(); var export = Button("Export Profile", model.ExportProfile); dataActions.Children.Add(export); dataActions.Children.Add(Button("Import Profile", model.ImportProfile)); learning.Children.Add(dataActions);
        var dataMessage = Caption(learning, ""); refresh.Add(() => { export.IsEnabled = model.Vocabulary.TrackedCount > 0; dataMessage.Text = model.DataMessage ?? ""; dataMessage.Visibility = string.IsNullOrWhiteSpace(model.DataMessage) ? Visibility.Collapsed : Visibility.Visible; });
        var reset = Button("Reset what Babelstårnet has learned", model.ResetProfile); reset.Foreground = Ui.ColorBrush(172, 49, 44); learning.Children.Add(reset); refresh.Add(() => reset.IsEnabled = model.Vocabulary.TrackedCount > 0);

        var engines = Section("Local engines");
        Value(engines, "OCR", () => model.OcrReady ? "Windows Danish OCR · ready" : "Danish OCR not installed");
        Value(engines, "Translation", () => model.TranslationReady ? "Argos Danish → English · ready" : "Local resources not installed");
        Value(engines, "Speech", () => model.VoiceReady ? "Local voice ready" : "Voice not installed");
        var engineActions = new WrapPanel(); var check = Button("Check engines", model.CheckEngines); var install = Button("Install / repair translation", model.InstallTranslation); engineActions.Children.Add(check); engineActions.Children.Add(install); engines.Children.Add(engineActions);
        refresh.Add(() => { check.IsEnabled = !model.Installing && !model.Busy; install.IsEnabled = !model.Installing; });
        var failure = Caption(engines, ""); refresh.Add(() => { failure.Text = model.Failure ?? ""; failure.Visibility = model.Failure is null ? Visibility.Collapsed : Visibility.Visible; });

        var contextual = Section("Contextual meanings");
        Toggle(contextual, "Translate words in their sentence", () => model.Preferences.ContextualMeanings, v => model.Preferences.ContextualMeanings = v, () => model.ContextReady);
        Value(contextual, "Model", () => model.ContextReady ? "Gemma 3 4B · local" : "Not installed");
        Caption(contextual, "Uses the sentence to choose the word’s meaning and dictionary form, with a short Danish explanation. Runs entirely on this PC. The optional model is about 3.3 GB; existing local weights are reused.");
        var contextActions = new WrapPanel(); var contextInstall = Button("Install model", model.InstallContext); var contextCheck = Button("Check model", model.CheckContext);
        contextActions.Children.Add(contextInstall); contextActions.Children.Add(contextCheck); var runtime = Button("Get Ollama for Windows", model.GetContextRuntime); contextActions.Children.Add(runtime); contextual.Children.Add(contextActions);
        var contextStatus = Caption(contextual, "");
        refresh.Add(() => { contextInstall.IsEnabled = model.ContextRuntimeReady && !model.ContextBusy; contextCheck.IsEnabled = model.ContextReady && !model.ContextBusy;
            runtime.Visibility = model.ContextRuntimeReady ? Visibility.Collapsed : Visibility.Visible; contextStatus.Text = model.ContextBusy ? "Preparing the local model…" : model.ContextMessage ?? ""; });

        var appearance = Section("Appearance");
        var themes = new ComboBox { Width = 216, ItemsSource = new[] { "Use Windows setting", "Light", "Dark" }, SelectedIndex = model.Preferences.Appearance == "light" ? 1 : model.Preferences.Appearance == "dark" ? 2 : 0 };
        FormControls.Apply(themes); Row(appearance, "App theme", themes);
        themes.SelectionChanged += (_, _) => { if (!refreshing) { model.Preferences.Appearance = themes.SelectedIndex == 1 ? "light" : themes.SelectedIndex == 2 ? "dark" : "system"; model.Commit(); } };
        refresh.Add(() => themes.SelectedIndex = model.Preferences.Appearance == "light" ? 1 : model.Preferences.Appearance == "dark" ? 2 : 0);
        Caption(appearance, "Follows Windows colors by default. High contrast and reduced motion follow your accessibility settings.");

        var access = Section("Access");
        Value(access, "Screen capture", () => "Available to desktop apps"); access.Children.Add(Button("Open Windows language settings", model.OpenLanguageSettings));
        Caption(access, "Screenshots, recognized text, translations and speech remain on this PC. Secure desktops and apps that block capture cannot be read.");
        Loaded += (_, _) => Refresh(); Unloaded += (_, _) => model.Changed -= Refresh; model.Changed += Refresh; Refresh();
    }
    private static string Words(int count) => count + (count == 1 ? " word" : " words");
    private StackPanel Section(string title)
    {
        var heading = Ui.Text(title, 12, true); heading.Foreground = Ui.Muted; heading.Margin = new Thickness(10, form.Children.Count == 0 ? 0 : 20, 0, 7); form.Children.Add(heading);
        var panel = new StackPanel { Margin = new Thickness(13, 9, 13, 9) };
        var card = new Border { CornerRadius = new CornerRadius(8), Background = Ui.Surface, BorderBrush = Ui.Stroke, BorderThickness = new Thickness(1), Child = panel }; form.Children.Add(card); sections[title] = [heading, card]; return panel;
    }
    private static TextBlock Caption(Panel parent, string text)
    { var block = Ui.Text(text, 11); block.Foreground = Ui.Muted; block.Margin = new Thickness(0, 5, 0, 8); parent.Children.Add(block); return block; }
    private static void Row(Panel parent, string label, FrameworkElement value)
    {
        var grid = new Grid { Margin = new Thickness(0, 5, 0, 5) }; grid.ColumnDefinitions.Add(new ColumnDefinition()); grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var text = Ui.Text(label, 12); text.Margin = new Thickness(0, 0, 8, 0); text.VerticalAlignment = VerticalAlignment.Center; grid.Children.Add(text); Grid.SetColumn(value, 1); grid.Children.Add(value); parent.Children.Add(grid);
    }
    private void Value(Panel parent, string label, Func<string> value)
    { var text = Ui.Text("", 11); text.Foreground = Ui.Muted; text.Margin = new Thickness(0); text.MaxWidth = 228; text.TextAlignment = TextAlignment.Right; Row(parent, label, text); refresh.Add(() => text.Text = value()); }
    private void Toggle(Panel parent, string label, Func<bool> get, Action<bool> set, Func<bool>? enabled = null)
    {
        var check = new CheckBox { Content = label, FontFamily = Ui.Font, FontSize = 12, Margin = new Thickness(0, 6, 0, 6), IsChecked = get() };
        FormControls.Apply(check);
        check.Checked += (_, _) => Change(); check.Unchecked += (_, _) => Change();
        void Change() { if (refreshing) return; set(check.IsChecked == true); model.Commit(); }
        parent.Children.Add(check); refresh.Add(() => { check.IsChecked = get(); check.IsEnabled = enabled?.Invoke() ?? true; });
    }
    private static Button Button(string title, Action action) { var button = Ui.Button(title, action); button.FontSize = 11; button.MinHeight = 27; button.Padding = new Thickness(8, 4, 8, 4); return button; }
    public void Refresh() { if (refreshing) return; refreshing = true; try { foreach (var action in refresh) action(); } finally { refreshing = false; } }
}
