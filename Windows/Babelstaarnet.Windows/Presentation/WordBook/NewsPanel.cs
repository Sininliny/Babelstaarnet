using System;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;

namespace Babelstaarnet.Windows;

internal sealed class NewsPanel : ScrollViewer
{
    private readonly NewsService news;
    private readonly StackPanel body = new() { Margin = new Thickness(22) };
    public NewsPanel(NewsService news)
    {
        this.news = news; Content = body; Background = Ui.Paper; VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
        Loaded += async (_, _) => { news.PageVisible = true; news.Changed += Render; Render(); await news.RefreshAsync(); };
        Unloaded += (_, _) => { news.PageVisible = false; news.Changed -= Render; }; Render();
    }
    private void Render()
    {
        body.Children.Clear(); body.Children.Add(Ui.Text("Read something new", 24, true));
        Add("DR news · optional internet feature. Headlines are matched to recent learning on this PC.");
        var enabled = new CheckBox { Content = "News recommendations (internet)", IsChecked = news.Preferences.Enabled, Margin = new Thickness(0, 12, 0, 8), Foreground = Ui.Ink };
        FormControls.Apply(enabled);
        body.Children.Add(enabled);
        enabled.Click += async (_, _) => { news.Configure(enabled.IsChecked == true, news.Preferences.Background, news.Preferences.Notify, news.Preferences.Topic, news.Preferences.DigestHour); await news.RefreshAsync(); };
        Add(NewsService.Disclosure);
        var actions = new WrapPanel { Margin = new Thickness(0, 12, 0, 10) };
        var topics = new ComboBox { ItemsSource = NewsService.Topics, SelectedIndex = news.Preferences.Topic, Width = 170, Margin = new Thickness(0, 0, 8, 0), IsEnabled = !news.Busy };
        FormControls.Apply(topics); actions.Children.Add(topics);
        topics.SelectionChanged += async (_, _) => { if (topics.SelectedIndex < 0 || topics.SelectedIndex == news.Preferences.Topic) return; news.Configure(news.Preferences.Enabled, news.Preferences.Background, news.Preferences.Notify, topics.SelectedIndex, news.Preferences.DigestHour); await news.RefreshAsync(true); };
        var refresh = Ui.Button(news.Busy ? "Fetching…" : "Refresh", () => _ = news.RefreshAsync(true)); refresh.IsEnabled = news.Preferences.Enabled && !news.Busy; actions.Children.Add(refresh);
        actions.Children.Add(Ui.Button("Another group", news.NextGroup));
        var updates = Ui.Button("Show new content", news.AcceptUpdates); updates.IsEnabled = news.HasUpdates; actions.Children.Add(updates);
        body.Children.Add(actions); var status = Ui.Text(news.Status, 12); status.Foreground = Ui.Muted; status.MinHeight = 32; body.Children.Add(status);
        foreach (var card in news.Cards)
        {
            var article = card.Article; var content = new StackPanel { Margin = new Thickness(16) };
            content.Children.Add(Ui.Text(article.Title, 18, true));
            var date = Ui.Text("DR · " + DateTimeOffset.FromUnixTimeSeconds((long)article.Published).ToLocalTime().ToString("g"), 11); date.Foreground = Ui.Muted; date.Margin = new Thickness(0, 6, 0, 8); content.Children.Add(date);
            if (article.Summary.Length > 0) content.Children.Add(Ui.Text(article.Summary, 13));
            if (news.Simplified(article) is { } shortText)
            { content.Children.Add(Ui.Text("On-device AI · simplified RSS excerpt · " + news.SimplifiedModel(article) + " · compare above", 10)); content.Children.Add(Ui.Text(shortText, 13)); }
            if (news.SimplificationState(article) is { } state) content.Children.Add(Ui.Text(state, 11));
            if (card.Matches.Length > 0) { var match = Ui.Text("Title / summary includes: " + string.Join(" · ", card.Matches), 11); match.Foreground = Ui.Accent; match.Margin = new Thickness(0, 8, 0, 8); content.Children.Add(match); }
            var buttons = new WrapPanel { Margin = new Thickness(0, 10, 0, 0) };
            buttons.Children.Add(Ui.Button("Read original · browser / internet", () => { if (NewsService.ValidArticle(article)) Process.Start(new ProcessStartInfo(article.Url) { UseShellExecute = true }); news.MarkSeen(article); }));
            buttons.Children.Add(Ui.Button("Already seen", () => news.MarkSeen(article))); content.Children.Add(buttons);
            if (article.Summary.Length > 0) buttons.Children.Add(Ui.Button("Simplify excerpt · local AI", () => _ = news.SimplifyAsync(article)));
            body.Children.Add(new Border { Child = content, Background = Ui.Surface, BorderBrush = Ui.Stroke, BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(8), Margin = new Thickness(0, 14, 0, 0) });
        }
        if (news.Cards.Count == 0 && !news.Busy) Add("No suitable new content yet. Try a different topic or come back later.");
    }
    private void Add(string text) { var label = Ui.Text(text, 12); label.Foreground = Ui.Muted; label.Margin = new Thickness(0, 7, 0, 0); body.Children.Add(label); }
}
