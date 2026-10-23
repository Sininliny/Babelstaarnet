using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace Babelstaarnet.Windows;
internal sealed class NewsPanel : ScrollViewer
{
    private readonly NewsService news;
    private readonly Action? openSettings;
    private readonly StackPanel body = new() { Margin = new Thickness(22) };
    private readonly List<NewsReadingCard> cards = [];
    public NewsPanel(NewsService news, Action? openSettings = null)
    {
        this.news = news; this.openSettings = openSettings; Content = body; Background = Ui.Paper; VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
        Loaded += async (_, _) => { news.PageVisible = true; news.Changed += NewsChanged; news.Reader.Changed += ReadingChanged; Render(); await news.RefreshAsync(); await PrepareVisible(); };
        Unloaded += (_, _) => { news.PageVisible = false; news.Changed -= NewsChanged; news.Reader.Changed -= ReadingChanged; news.Reader.Cancel(); }; Render();
    }
    private void NewsChanged() { Render(); if (IsLoaded) _ = PrepareVisible(); }
    private void ReadingChanged() { foreach (var card in cards) card.UpdateSupport(); }
    private async Task PrepareVisible() { foreach (var article in news.Cards.Select(c => c.Article).ToArray()) { if (!IsLoaded) break; await news.Reader.PrepareAsync(article); } }
    private void Render()
    {
        body.Children.Clear(); cards.Clear(); body.Children.Add(Ui.Text("Read something new", 24, true));
        Add("Fresh Danish, with English to help you read. Select a Danish word for its meaning, pronunciation or Word Book.");
        var options = new WrapPanel { Margin = new Thickness(0, 8, 0, 4) };
        var enabled = new CheckBox { Content = "DR news · internet", IsChecked = news.Preferences.Enabled, Margin = new Thickness(0, 7, 22, 6) }; FormControls.Apply(enabled); options.Children.Add(enabled);
        enabled.Click += async (_, _) => { news.Configure(enabled.IsChecked == true, news.Preferences.Background, news.Preferences.Notify, news.Preferences.Topic, news.Preferences.DigestHour); await news.RefreshAsync(); };
        var english = new CheckBox { Content = "English support", IsChecked = news.Reader.ShowEnglish, Margin = new Thickness(0, 7, 22, 6), ToolTip = "On by default. Turn off to try Danish first; Show English stays available." }; FormControls.Apply(english); options.Children.Add(english);
        english.Click += async (_, _) => { news.Reader.SetEnglish(english.IsChecked == true); await PrepareVisible(); };
        if (openSettings is not null) options.Children.Add(Ui.Button("News settings", openSettings)); body.Children.Add(options);
        var privacy = new Expander { Header = news.Preferences.Enabled ? "DR news · internet is on · privacy details" : "About connecting to DR", Foreground = Ui.Muted, FontFamily = Ui.Font, FontSize = 11, Margin = new Thickness(0, 0, 0, 10), IsExpanded = !news.Preferences.Enabled };
        privacy.Content = Ui.Text(NewsService.Disclosure, 11); body.Children.Add(privacy);
        var actions = new WrapPanel { Margin = new Thickness(0, 5, 0, 4) };
        var topics = new ComboBox { ItemsSource = NewsService.Topics, SelectedIndex = news.Preferences.Topic, Width = 165, Margin = new Thickness(0, 0, 8, 8), IsEnabled = !news.Busy }; FormControls.Apply(topics); actions.Children.Add(topics);
        topics.SelectionChanged += async (_, _) => { if (topics.SelectedIndex < 0 || topics.SelectedIndex == news.Preferences.Topic) return; news.Configure(news.Preferences.Enabled, news.Preferences.Background, news.Preferences.Notify, topics.SelectedIndex, news.Preferences.DigestHour); await news.RefreshAsync(true); };
        var refresh = Ui.Button(news.Busy ? "Fetching…" : "Refresh", () => _ = news.RefreshAsync(true)); refresh.IsEnabled = news.Preferences.Enabled && !news.Busy; actions.Children.Add(refresh);
        actions.Children.Add(Ui.Button("Another group", news.NextGroup));
        if (news.HasUpdates) actions.Children.Add(Ui.Button("Show new content", news.AcceptUpdates));
        body.Children.Add(actions); Add(news.Status);
        foreach (var card in news.Cards) { var view = new NewsReadingCard(news, card); cards.Add(view); body.Children.Add(view); }
        if (news.Cards.Count == 0 && !news.Busy) Add("No suitable new content yet. Try a different topic or come back later.");
    }
    private void Add(string text) { var label = Ui.Text(text, 12); label.Foreground = Ui.Muted; label.Margin = new Thickness(0, 4, 0, 6); body.Children.Add(label); }
}

internal sealed class NewsReadingCard : Border
{
    private readonly NewsService news;
    private readonly NewsCard card;
    private readonly StackPanel titleEnglish = new(), summaryEnglish = new(), wordHelp = new();
    public NewsReadingCard(NewsService news, NewsCard card)
    {
        this.news = news; this.card = card;
        Background = Ui.Surface; BorderBrush = Ui.Stroke; BorderThickness = new Thickness(1); CornerRadius = new CornerRadius(10); Margin = new Thickness(0, 12, 0, 0);
        var content = new StackPanel { Margin = new Thickness(18) }; Child = content;
        var date = Ui.Text("DR · " + DateTimeOffset.FromUnixTimeSeconds((long)card.Article.Published).ToLocalTime().ToString("g"), 11); date.Foreground = Ui.Muted; content.Children.Add(date);
        var hint = Ui.Text("DANISH · SELECT A WORD FOR HELP", 10); hint.Foreground = Ui.Muted; content.Children.Add(hint);
        content.Children.Add(Source(card.Article.Title, true)); content.Children.Add(titleEnglish);
        if (card.Article.Summary.Length > 0) { content.Children.Add(Source(card.Article.Summary, false)); content.Children.Add(summaryEnglish); }
        else { var note = Ui.Text("Headline only · DR did not include an excerpt.", 11); note.Foreground = Ui.Muted; content.Children.Add(note); }
        content.Children.Add(wordHelp);
        if (news.Simplified(card.Article) is { } text) { content.Children.Add(Ui.Text("Simpler Danish · on-device AI · compare with the DR text above", 10)); content.Children.Add(Source(text, false)); }
        if (news.SimplificationState(card.Article) is { } state) content.Children.Add(Ui.Text(state, 11));
        if (card.Matches.Length > 0) { var match = Ui.Text("From your recent words: " + string.Join(" · ", card.Matches), 11); match.Foreground = Ui.Accent; content.Children.Add(match); }
        var reading = new WrapPanel { Margin = new Thickness(0, 10, 0, 0) };
        var listen = Ui.Button("Listen to headline", () => news.Reader.Speak?.Invoke(card.Article.Title)); listen.IsEnabled = news.Reader.Speak is not null; reading.Children.Add(listen);
        reading.Children.Add(Ui.Button(card.Article.Summary.Length == 0 ? "Simpler headline · local AI" : "Simpler excerpt · local AI", () => _ = news.SimplifyAsync(card.Article))); content.Children.Add(reading);
        var links = new WrapPanel(); links.Children.Add(Ui.Button("Full story · browser / internet", () => { if (NewsService.ValidArticle(card.Article)) Process.Start(new ProcessStartInfo(card.Article.Url) { UseShellExecute = true }); news.MarkSeen(card.Article); })); links.Children.Add(Ui.Button("Already seen", () => news.MarkSeen(card.Article))); content.Children.Add(links);
        UpdateSupport();
    }
    private WrapPanel Source(string text, bool headline)
    {
        var line = new WrapPanel { Margin = new Thickness(0, 0, 0, 8) };
        foreach (string piece in NewsReadingSupport.Pieces(text))
        {
            if (NewsReadingSupport.Word(piece) is { } word)
            {
                var button = Ui.ActionButton(piece, () => _ = news.Reader.LookupAsync(word, card.Article, text));
                button.FontSize = headline ? 18 : 13; button.FontWeight = headline ? FontWeights.SemiBold : FontWeights.Normal;
                button.Padding = new Thickness(1, 2, 1, 2); button.MinHeight = 24; button.Margin = new Thickness(0, 0, 4, 3); button.BorderThickness = new Thickness(0); button.MaxWidth = 390;
                button.Background = card.Matches.Contains(word, StringComparer.OrdinalIgnoreCase) ? Ui.AccentSoft : Brushes.Transparent;
                button.ToolTip = "Meaning of " + word; System.Windows.Automation.AutomationProperties.SetName(button, "Look up Danish word " + word); line.Children.Add(button);
            }
            else { var label = Ui.Text(piece, headline ? 18 : 13, headline); label.Margin = new Thickness(0, 2, 4, 3); line.Children.Add(label); }
        }
        return line;
    }
    public void UpdateSupport()
    {
        titleEnglish.Children.Clear(); summaryEnglish.Children.Clear(); wordHelp.Children.Clear(); var reader = news.Reader;
        if (reader.IsVisible(card.Article))
        {
            if (reader.Meaning(card.Article) is { } english)
            {
                void Add(Panel panel, string value) { var box = new StackPanel(); var caption = Ui.Text("ENGLISH · ON THIS DEVICE", 10); caption.Foreground = Ui.Muted; box.Children.Add(caption); box.Children.Add(Ui.Text(value, 14)); panel.Children.Add(new Border { Background = Ui.Paper, CornerRadius = new CornerRadius(6), Padding = new Thickness(10), Margin = new Thickness(0, 0, 0, 10), Child = box }); }
                Add(titleEnglish, english.Parts[0]); if (english.Parts.Length > 1) Add(summaryEnglish, english.Parts[1]);
            }
            else { titleEnglish.Children.Add(Ui.Text(reader.State(card.Article) ?? "Preparing English on this device…", 11)); titleEnglish.Children.Add(Ui.Button("Try English again", () => _ = reader.PrepareAsync(card.Article, true))); }
        }
        else titleEnglish.Children.Add(Ui.Button("Show English", () => _ = reader.PrepareAsync(card.Article, true)));
        if (reader.Selected is { } selected && selected.ArticleKey == NewsReadingSupport.Key(card.Article))
        {
            var box = new StackPanel(); box.Children.Add(Ui.Text(selected.Word, 15, true));
            if (selected.Meaning.Length > 0) box.Children.Add(Ui.Text(selected.Meaning, 14));
            var note = Ui.Text(selected.Status, 11); note.Foreground = Ui.Muted; box.Children.Add(note);
            var buttons = new WrapPanel(); var speak = Ui.Button("Listen to word", () => reader.Speak?.Invoke(selected.Word)); speak.IsEnabled = reader.Speak is not null; buttons.Children.Add(speak);
            var save = Ui.Button(selected.Saved ? "Saved to Word Book" : "Save word", () => reader.SaveSelection(card.Article)); save.IsEnabled = !selected.Saved && selected.Meaning.Length > 0 && reader.SaveWord is not null; buttons.Children.Add(save); box.Children.Add(buttons);
            wordHelp.Children.Add(new Border { Child = box, Padding = new Thickness(12), CornerRadius = new CornerRadius(8), Background = Ui.AccentSoft, Margin = new Thickness(0, 0, 0, 10) });
        }
    }
}
