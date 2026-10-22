using Babelstaarnet.Core;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace Babelstaarnet.Windows;

internal sealed class BridgeLine : WrapPanel
{
    private readonly List<(Grid Unit, TextBlock Text, Border Tint, Border Focus)> units = [];
    private BridgeToken[] previous = [];
    private static Brush TintBrush => WindowsTheme.Current.EnglishTint;
    private static Brush FocusBrush => WindowsTheme.Current.Focus;
    internal int Updates { get; private set; }
    public void SetTokens(IReadOnlyList<BridgeToken> tokens)
    {
        var grouped = new List<BridgeToken>();
        foreach (var token in tokens)
            if (token.English && grouped.Count > 0 && grouped[^1].English && grouped[^1].Focus == token.Focus)
                grouped[^1] = grouped[^1] with { Text = grouped[^1].Text + " " + token.Text };
            else grouped.Add(token);
        if (previous.SequenceEqual(grouped)) return;
        previous = grouped.ToArray(); Updates++;
        int total = tokens.Sum(t => t.Text.Split(' ', StringSplitOptions.RemoveEmptyEntries).Length);
        int english = tokens.Where(t => t.English).Sum(t => t.Text.Split(' ', StringSplitOptions.RemoveEmptyEntries).Length);
        bool marksSwaps = total > 0 && (double)english / total <= .66;
        while (units.Count > grouped.Count) { Children.Remove(units[^1].Unit); units.RemoveAt(units.Count - 1); }
        for (int i = 0; i < grouped.Count; i++)
        {
            if (i >= units.Count)
            {
                var text = OverlayCard.Label(12);
                var tint = new Border { CornerRadius = new CornerRadius(4), Margin = new Thickness(-3, -1, -3, -1), IsHitTestVisible = false };
                var focus = new Border { Height = 1.5, Background = FocusBrush, VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(-1, 0, -1, -2.5), IsHitTestVisible = false };
                var unit = new Grid { Margin = new Thickness(0, 0, 5, 5), MaxWidth = 394 };
                unit.Children.Add(tint); unit.Children.Add(text); unit.Children.Add(focus); units.Add((unit, text, tint, focus)); Children.Add(unit);
            }
            var current = units[i]; var value = grouped[i];
            current.Text.Text = value.Text; current.Text.FontWeight = value.English ? FontWeights.Medium : FontWeights.Normal;
            current.Text.Opacity = value.English ? 1 : DanishLanguage.KnowledgeOpacity(value.KnowledgeLevel);
            current.Tint.Background = value.English && marksSwaps ? TintBrush : Brushes.Transparent;
            current.Focus.Visibility = value.Focus ? Visibility.Visible : Visibility.Collapsed;
        }
    }
}

internal sealed class SentenceCard : Border
{
    private readonly BridgeLine line = new();
    private readonly TextBlock confirmation = OverlayCard.Label(10), directMeaning = OverlayCard.Label(11);
    private bool standalone;
    private readonly Button sentenceHelp;
    private readonly TextBlock fullMeaning = OverlayCard.Label(12);
    public event Action? SentenceMeaningRequested;
    public SentenceCard()
    {
        OverlayCard.StylePanel(this, OverlayLayout.SentenceWidth, 12, 8); MinHeight = 76;
        var panel = new StackPanel(); panel.Children.Add(line); directMeaning.Foreground = OverlayCard.Secondary;
        directMeaning.Opacity = .72; directMeaning.Margin = new Thickness(0, 5, 0, 0); panel.Children.Add(directMeaning);
        confirmation.Foreground = OverlayCard.Secondary; confirmation.Margin = new Thickness(0, 7, 0, 0); panel.Children.Add(confirmation);
        sentenceHelp = Ui.Button("See sentence meaning", () => SentenceMeaningRequested?.Invoke()); sentenceHelp.FontSize = 10; sentenceHelp.Padding = new Thickness(5, 3, 5, 3); sentenceHelp.MinHeight = 24;
        sentenceHelp.HorizontalAlignment = HorizontalAlignment.Left; sentenceHelp.Margin = new Thickness(0, 5, 0, 0);
        panel.Children.Add(fullMeaning); panel.Children.Add(sentenceHelp);
        fullMeaning.Visibility = Visibility.Collapsed;
        confirmation.Visibility = directMeaning.Visibility = Visibility.Collapsed; Child = panel;
    }
    public void SetSentenceMeaning(string text, bool requested)
    {
        sentenceHelp.Content = requested ? "Show reading bridge" : "See sentence meaning";
        line.Visibility = requested ? Visibility.Collapsed : Visibility.Visible;
        fullMeaning.Visibility = requested ? Visibility.Visible : Visibility.Collapsed;
        fullMeaning.Text = text.Length > 0 ? text : "Translating locally…";
    }
    public void SetContent(IReadOnlyList<BridgeToken> tokens) => line.SetTokens(tokens);
    public void SetMode(bool standsAlone, string meaning, int level)
    {
        standalone = standsAlone; directMeaning.Text = meaning;
        directMeaning.Visibility = standalone && meaning.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
        if (!standalone) confirmation.Visibility = Visibility.Collapsed;
    }
    public void SetFeedback(bool? known)
    {
        confirmation.Text = known == true ? "✓  Marked known" : "✓  English restored";
        confirmation.Visibility = standalone && known is not null ? Visibility.Visible : Visibility.Collapsed;
    }
}
