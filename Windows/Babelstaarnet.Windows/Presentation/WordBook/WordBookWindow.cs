using Babelstaarnet.Core;
using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;

namespace Babelstaarnet.Windows;

internal sealed class WordBookWindow : Window
{
    public WordBookWindow(VocabularyStore store, Action<string> speak, ReaderPreferences? preferences = null, Action? fillMeanings = null, NewsService? news = null)
    {
        Title = "Babelstårnet · Word Book"; Icon = BrandIcons.AppImage;
        WindowsTheme.Current.Attach(this);
        Width = 860; Height = 600; MinWidth = 620; MinHeight = 360; Background = Ui.Surface;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        var view = new WordBookPanel(store, speak, preferences ?? new ReaderPreferences()); Content = view;
        if (news is not null) { var tabs = new TabControl(); tabs.Items.Add(new TabItem { Header = "Words", Content = view }); tabs.Items.Add(new TabItem { Header = "Read something new · internet", Content = new NewsPanel(news) }); tabs.SelectedIndex = Math.Clamp(news.Preferences.LastBookPage, 0, 1); tabs.SelectionChanged += (sender, e) => { if (ReferenceEquals(e.Source, tabs)) news.SetBookPage(tabs.SelectedIndex); }; Content = tabs; }
        PreviewKeyDown += (_, e) => { if (Content is not TabControl tabs || tabs.SelectedIndex == 0) view.HandleReviewKey(e); };
        Loaded += (_, _) => fillMeanings?.Invoke();
    }
    public void OpenNews() { if (Content is TabControl tabs) tabs.SelectedIndex = 1; }
}

internal sealed class WordBookPanel : Grid
{
    private readonly VocabularyStore store;
    private readonly Action<string> speak;
    private readonly ReaderPreferences preferences;
    private readonly TextBox search = new() { Width = 220, Padding = new Thickness(7, 5, 7, 5), FontSize = 12, VerticalContentAlignment = VerticalAlignment.Center };
    private readonly TextBlock count = Ui.Text("", 11);
    private readonly ListBox list = new() { BorderThickness = new Thickness(0), Background = Ui.Surface, HorizontalContentAlignment = HorizontalAlignment.Stretch, Padding = new Thickness(0) };
    private readonly DockPanel listFrame = new();
    private readonly StackPanel empty = new() { Margin = new Thickness(30, 70, 30, 30), HorizontalAlignment = HorizontalAlignment.Center };
    private readonly Button[] filters;
    private readonly Button reviewButton;
    private string filter = "All";
    private WordReviewSession? review;
    internal int RowBuilds { get; private set; }
    internal sealed record BookRow(VocabularyEntry Entry, WordBookPanel Owner);
    internal sealed class RowHost : ContentControl
    {
        public RowHost() => DataContextChanged += (_, _) =>
        {
            if (DataContext is BookRow row) { Content = row.Owner.Row(row.Entry); } else Content = null;
        };
    }
    internal WordReviewSession? ReviewSession => review;
    public WordBookPanel(VocabularyStore store, Action<string> speak, ReaderPreferences preferences)
    {
        this.store = store; this.speak = speak; this.preferences = preferences; Background = Ui.Paper;
        ScrollViewer.SetCanContentScroll(list, true); VirtualizingPanel.SetIsVirtualizing(list, true);
        VirtualizingPanel.SetVirtualizationMode(list, VirtualizationMode.Recycling);
        var rowTemplate = new DataTemplate(typeof(BookRow)) { VisualTree = new FrameworkElementFactory(typeof(RowHost)) }; list.ItemTemplate = rowTemplate;
        var menu = new ContextMenu(); list.ContextMenu = menu;
        list.PreviewMouseRightButtonDown += (_, e) =>
        {
            if (ItemsControl.ContainerFromElement(list, e.OriginalSource as DependencyObject) is ListBoxItem item) item.IsSelected = true;
        };
        list.ContextMenuOpening += (_, e) =>
        {
            menu.Items.Clear(); if (list.SelectedItem is not BookRow selected) { e.Handled = true; return; }
            var entry = selected.Entry;
            menu.Items.Add(new MenuItem { Header = "Say It", Command = new UiCommand(() => speak(entry.Word)) });
            menu.Items.Add(new MenuItem { Header = "I Know This Now", Command = new UiCommand(() => store.Mark(entry.Word, true, DateTimeOffset.Now)) });
            menu.Items.Add(new Separator()); menu.Items.Add(new MenuItem { Header = "Remove from Word Book", Command = new UiCommand(() => store.RemoveSaved(entry.Key)) });
        };
        TextElement.SetFontFamily(this, Ui.Font);
        var frame = listFrame; Children.Add(frame);
        var toolbar = new WrapPanel { Margin = new Thickness(16, 12, 16, 10), VerticalAlignment = VerticalAlignment.Center };
        search.ToolTip = "Search words, meanings, or sentences"; System.Windows.Automation.AutomationProperties.SetName(search, "Search Word Book");
        var searchField = new Grid(); searchField.Children.Add(search); var placeholder = Ui.Text("Search", 12); placeholder.Margin = new Thickness(8, 6, 0, 0); placeholder.Foreground = Ui.Muted; placeholder.IsHitTestVisible = false; searchField.Children.Add(placeholder); toolbar.Children.Add(searchField);
        search.TextChanged += (_, _) => placeholder.Visibility = search.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        var segments = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(12, 0, 12, 0) };
        filters = new[] { "All", "Learning", "Known" }.Select(title => SmallButton(title, () => { filter = title; Refresh(); })).ToArray();
        foreach (var button in filters) { button.Margin = new Thickness(0); segments.Children.Add(button); } toolbar.Children.Add(segments);
        count.Margin = new Thickness(0, 7, 12, 0); count.Foreground = Ui.Muted; toolbar.Children.Add(count);
        toolbar.Children.Add(SmallButton("Export", Export)); reviewButton = SmallButton("Review", BeginReview); toolbar.Children.Add(reviewButton);
        DockPanel.SetDock(toolbar, Dock.Top); frame.Children.Add(toolbar);
        var body = new Grid(); body.Children.Add(list);
        empty.Children.Add(Ui.Text("Your Word Book", 20, true));
        var guidance = Ui.Text($"When a bubble is open, press {preferences.Shortcuts.DontKnow.Display} for Don’t know or {preferences.Shortcuts.TogglePin.Display} to pin a word. It will be saved here for later.", 12);
        guidance.MaxWidth = 350; guidance.Foreground = Ui.Muted; guidance.TextAlignment = TextAlignment.Center; empty.Children.Add(guidance); body.Children.Add(empty); frame.Children.Add(body);
        search.TextChanged += (_, _) => Refresh();
        Loaded += (_, _) => { store.Changed += StoreChanged; Refresh(); }; Unloaded += (_, _) => store.Changed -= StoreChanged; Refresh();
    }
    private void StoreChanged() { if (review is null) Refresh(); }
    private static Button SmallButton(string text, Action action)
    { var button = Ui.Button(text, action); button.FontSize = 11; button.MinHeight = 29; button.Padding = new Thickness(9, 5, 9, 5); button.Margin = new Thickness(0, 0, 6, 0); return button; }
    private void Refresh()
    {
        if (review is not null) return;
        var all = store.Saved.ToArray(); string query = search.Text.Trim();
        var entries = all.Where(e => (filter == "All" || (filter == "Known") == (e.EffectiveLevel(DateTimeOffset.Now) >= 3)) &&
            (e.Word.Contains(query, StringComparison.OrdinalIgnoreCase) || e.Meaning.Contains(query, StringComparison.OrdinalIgnoreCase) || e.Sentence.Contains(query, StringComparison.OrdinalIgnoreCase))).ToArray();
        string? selectedKey = (list.SelectedItem as BookRow)?.Entry.Key;
        list.ItemsSource = entries.Select(e => new BookRow(e, this)).ToArray();
        if (selectedKey is not null) list.SelectedItem = list.Items.Cast<BookRow>().FirstOrDefault(row => row.Entry.Key == selectedKey);
        count.Text = all.Length + (all.Length == 1 ? " word" : " words"); int due = all.Count(e => e.DueAt <= DateTimeOffset.Now);
        reviewButton.Content = due > 0 ? $"Review ({due})" : "Review"; reviewButton.IsEnabled = due > 0;
        foreach (var button in filters) { button.Background = (string)button.Content == filter ? Ui.AccentSoft : Ui.Surface; button.Foreground = (string)button.Content == filter ? Ui.Accent : Ui.Ink; }
        empty.Visibility = entries.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        ((TextBlock)empty.Children[0]).Text = all.Length == 0 ? "Your Word Book" : "No matching words";
        empty.Children[1].Visibility = all.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
    }
    private FrameworkElement Row(VocabularyEntry entry)
    {
        RowBuilds++;
        var grid = new Grid { Margin = new Thickness(16, 12, 12, 12) }; grid.ColumnDefinitions.Add(new ColumnDefinition()); grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(155) });
        var detail = new StackPanel();
        var first = new TextBlock { TextWrapping = TextWrapping.Wrap, Foreground = Ui.Ink, FontSize = 13 };
        first.Inlines.Add(new Run(entry.Word) { FontWeight = FontWeights.SemiBold, FontSize = 14 });
        if (entry.Meaning.Length > 0) first.Inlines.Add(new Run("   " + entry.Meaning) { Foreground = Ui.Muted }); detail.Children.Add(first);
        if (!string.IsNullOrEmpty(entry.Lemma) && !entry.Lemma.Equals(entry.Word, StringComparison.OrdinalIgnoreCase)) { var lemma = Ui.Text(entry.Lemma, 12); lemma.Foreground = Ui.Muted; lemma.Margin = new Thickness(0, 4, 0, 0); detail.Children.Add(lemma); }
        if (entry.Sentence.Length > 0) { var sentence = Ui.Text(entry.Sentence, 11); sentence.MaxHeight = 32; sentence.TextTrimming = TextTrimming.CharacterEllipsis; sentence.Foreground = Ui.Muted; sentence.Margin = new Thickness(0, 6, 12, 0); detail.Children.Add(sentence); } grid.Children.Add(detail);
        var metadata = new StackPanel { HorizontalAlignment = HorizontalAlignment.Right };
        var badge = Ui.Text(entry.Familiarity, 10); badge.Margin = new Thickness(7, 3, 7, 3);
        metadata.Children.Add(new Border { Background = entry.EffectiveLevel(DateTimeOffset.Now) >= 3 ? Ui.AccentSoft : Ui.Paper, CornerRadius = new CornerRadius(8), Child = badge });
        var bottom = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 5, 0, 0) };
        var due = Ui.Text(DueLabel(entry), 10); due.Foreground = Ui.Muted; due.Margin = new Thickness(0, 4, 8, 0); bottom.Children.Add(due);
        var speaker = SmallButton("Listen", () => speak(entry.Word)); speaker.Content = Ui.Icon("speaker", Ui.Muted, 13); speaker.ToolTip = "Say it"; speaker.Padding = new Thickness(5); speaker.MinHeight = 23; bottom.Children.Add(speaker); metadata.Children.Add(bottom);
        Grid.SetColumn(metadata, 1); grid.Children.Add(metadata);
        return new Border { Child = grid, BorderBrush = Ui.Stroke, BorderThickness = new Thickness(0, 0, 0, .5), Background = Ui.Surface };
    }

    private static string DueLabel(VocabularyEntry entry)
    { var span = entry.DueAt - DateTimeOffset.Now; return span <= TimeSpan.Zero ? "Ready to review" : span.TotalDays >= 1 ? $"In {(int)Math.Ceiling(span.TotalDays)} days" : span.TotalHours >= 1 ? $"In {(int)Math.Ceiling(span.TotalHours)} hours" : "Later today"; }
    private void Export()
    {
        var dialog = new Microsoft.Win32.SaveFileDialog { FileName = "Babelstaarnet-words.csv", Filter = "CSV files|*.csv" };
        if (dialog.ShowDialog(Window.GetWindow(this)) == true) File.WriteAllText(dialog.FileName, store.Csv(), new UTF8Encoding(true));
    }
    internal void BeginReview()
    {
        review = new WordReviewSession(store.Saved.Where(e => e.DueAt <= DateTimeOffset.Now).OrderBy(e => e.DueAt)); ShowReview();
        SpeakReviewWord();
    }
    private void SpeakReviewWord() { if (preferences.ReadAloud && review?.Current is { } entry) speak(entry.Word); }
    private void EndReview()
    {
        review = null; Children.Clear();
        // The original list frame stays alive while reviewing.
        Children.Add(listFrame);
        Refresh();
    }
    internal void Reveal() { if (review is null) return; review.Revealed = true; ShowReview(); }
    internal void Answer(bool remembered)
    {
        if (review?.Current is not { } entry || !review.Revealed) return;
        store.Review(entry.Key, remembered, DateTimeOffset.Now); review.Answer(remembered); ShowReview(); SpeakReviewWord();
    }
    private void ShowReview()
    {
        if (review is null) return;
        // Keep the list frame detached until review is finished.
        Children.Clear();
        var panel = new DockPanel { Margin = new Thickness(24) }; Children.Add(panel);
        var top = new DockPanel(); var done = SmallButton("Done", EndReview); DockPanel.SetDock(done, Dock.Left); top.Children.Add(done);
        var progress = Ui.Text(review.Current is null ? "Review complete" : $"{review.Position + 1} of {review.Count}", 12); progress.TextAlignment = TextAlignment.Right; progress.Foreground = Ui.Muted; top.Children.Add(progress); DockPanel.SetDock(top, Dock.Top); panel.Children.Add(top);
        var actions = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 12, 0, 0) }; DockPanel.SetDock(actions, Dock.Bottom); panel.Children.Add(actions);
        var card = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(30, 30, 30, 30) }; panel.Children.Add(card);
        if (review.Current is not { } entry)
        {
            var title = Ui.Text("All done for now", 24, true); title.TextAlignment = TextAlignment.Center; card.Children.Add(title);
            var result = Ui.Text($"{review.Remembered} remembered · {review.Forgotten} missed", 13); result.Foreground = Ui.Muted; result.TextAlignment = TextAlignment.Center; card.Children.Add(result);
            var back = SmallButton("Back to Word Book", EndReview); back.HorizontalAlignment = HorizontalAlignment.Center; card.Children.Add(back); return;
        }
        var wordRow = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center };
        wordRow.Children.Add(Ui.Text(entry.Word, 30, true)); var speaker = SmallButton("Listen", () => speak(entry.Word)); speaker.Content = Ui.Icon("speaker", Ui.Muted, 18); speaker.Background = Brushes.Transparent; speaker.BorderThickness = new Thickness(0); speaker.Margin = new Thickness(12, 0, 0, 6); wordRow.Children.Add(speaker); card.Children.Add(wordRow);
        if (entry.Sentence.Length > 0)
        {
            var sentence = Ui.Text("", 13); sentence.TextAlignment = TextAlignment.Center; sentence.Margin = new Thickness(0, 6, 0, 20); sentence.Foreground = Ui.Muted;
            int position = 0;
            foreach (System.Text.RegularExpressions.Match match in ReadingPolicy.Words().Matches(entry.Sentence))
            {
                sentence.Inlines.Add(new Run(entry.Sentence[position..match.Index])); sentence.Inlines.Add(new Run(match.Value) { FontWeight = ReadingPolicy.Key(match.Value) == entry.Key ? FontWeights.SemiBold : FontWeights.Normal }); position = match.Index + match.Length;
            }
            sentence.Inlines.Add(new Run(entry.Sentence[position..])); card.Children.Add(sentence);
        }
        if (!review.Revealed)
        { var reveal = SmallButton("Show meaning   Space", Reveal); reveal.HorizontalAlignment = HorizontalAlignment.Center; actions.Children.Add(reveal); }
        else
        {
            var meaning = Ui.Text(entry.Meaning.Length == 0 ? "No meaning saved" : entry.Meaning, 18); meaning.TextAlignment = TextAlignment.Center; meaning.Margin = new Thickness(0, 0, 0, 24); card.Children.Add(meaning);
            if (!string.IsNullOrEmpty(entry.Lemma)) { var lemma = Ui.Text("Dictionary form: " + entry.Lemma, 11); lemma.TextAlignment = TextAlignment.Center; lemma.Foreground = Ui.Muted; card.Children.Add(lemma); }
            actions.Children.Add(SmallButton("Didn’t know   2", () => Answer(false))); var knew = SmallButton("Knew it   1", () => Answer(true)); knew.Background = Ui.AccentSoft; actions.Children.Add(knew);
        }
    }
    internal void HandleReviewKey(KeyEventArgs e)
    {
        if (review is null) return;
        if (review.Current is null && e.Key == Key.Enter) { EndReview(); e.Handled = true; return; }
        if (e.Key == Key.Escape) { EndReview(); e.Handled = true; }
        else if (e.Key == Key.Space && review.Current is not null && !review.Revealed) { Reveal(); e.Handled = true; }
        else if (review.Revealed && e.Key is Key.D1 or Key.NumPad1 or Key.D2 or Key.NumPad2) { Answer(e.Key is Key.D1 or Key.NumPad1); e.Handled = true; }
    }
}

internal sealed class UiCommand(Action action) : ICommand
{
    public bool CanExecute(object? parameter) => true;
    public void Execute(object? parameter) => Ui.Try(action);
    public event EventHandler? CanExecuteChanged { add { } remove { } }
}
