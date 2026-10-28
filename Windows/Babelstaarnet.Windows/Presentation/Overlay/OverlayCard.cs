using Babelstaarnet.Core;
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace Babelstaarnet.Windows;

// Compact Windows lookup: familiar reading geometry with a system palette,
// rectangular quick actions, live text and an inline Danish speaker.
internal sealed class OverlayCard : Border
{
    private readonly TextBlock meaning = Label(16, true);
    private readonly TextBlock danish = Label(12);
    private readonly TextBlock knownState = Label(10);
    private readonly TextBlock knownKey = Label(10);
    private readonly TextBlock unknownKey = Label(10);
    private readonly TextBlock pinKey = Label(10);
    private readonly BridgeLine explanation = new();
    private HotKeyConfiguration shortcuts = HotKeyConfiguration.Defaults;
    private bool? feedback;
    private readonly Button known;
    private readonly Button unknown;
    private readonly Button pin;
    public event Action? Known;
    public event Action? Unknown;
    public event Action? Pin;
    public event Action? Listen;

    internal static Brush Primary => Ui.Ink;
    internal static Brush Secondary => Ui.Muted;
    internal static Brush ControlFill => WindowsTheme.Current.Control;
    internal static Brush ActiveFill => Ui.AccentSoft;
    internal static Brush Rule => Ui.Stroke;
    internal static Brush Material => Ui.Surface;

    internal static TextBlock Label(double size, bool bold = false) => new()
    {
        FontFamily = Ui.Font, FontSize = size, FontWeight = bold ? FontWeights.SemiBold : FontWeights.Normal,
        Foreground = Primary, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0)
    };
    internal static void StylePanel(Border panel, double width, double padding, double radius)
    {
        panel.Width = width;
        panel.Padding = new Thickness(padding);
        panel.Background = Material;
        panel.CornerRadius = new CornerRadius(radius);
        panel.BorderBrush = Ui.Stroke;
        panel.BorderThickness = new Thickness(.7);
        panel.UseLayoutRounding = true;
        TextOptions.SetTextFormattingMode(panel, TextFormattingMode.Display);
    }

    public OverlayCard()
    {
        StylePanel(this, OverlayLayout.WordWidth, 0, 8);
        MinHeight = 54;
        var panel = new StackPanel { Margin = new Thickness(11, 9, 11, 9) };
        var actions = new WrapPanel();
        known = Control("1", "Known", () => Known?.Invoke(), knownKey);
        unknown = Control("2", "Don't know", () => Unknown?.Invoke(), unknownKey);
        pin = Control("3", "Pin", () => Pin?.Invoke(), pinKey);
        SetShortcuts(shortcuts);
        actions.Children.Add(known); actions.Children.Add(unknown); actions.Children.Add(pin);
        panel.Children.Add(actions);
        panel.Children.Add(new Border { Height = 1, Background = Rule, Margin = new Thickness(0, 6, 0, 6) });
        meaning.Margin = new Thickness(0, 0, 0, 6);
        panel.Children.Add(meaning);
        var source = new Grid();
        source.ColumnDefinitions.Add(new ColumnDefinition());
        source.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var wordRow = new StackPanel { Orientation = Orientation.Horizontal };
        danish.Foreground = Secondary;
        danish.MaxWidth = 213;
        wordRow.Children.Add(danish);
        var speaker = Control("", "", () => Listen?.Invoke());
        speaker.Content = Ui.Icon("speaker", Secondary, 10);
        speaker.Background = Brushes.Transparent;
        speaker.Padding = new Thickness(3, 0, 3, 0);
        speaker.Margin = new Thickness(2, 0, 0, 0);
        speaker.ToolTip = "Pronounce the Danish word";
        AutomationProperties.SetName(speaker, "Pronounce the Danish word");
        wordRow.Children.Add(speaker);
        source.Children.Add(wordRow);
        knownState.Foreground = Secondary;
        knownState.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(knownState, 1); source.Children.Add(knownState);
        panel.Children.Add(source);
        explanation.Margin = new Thickness(0, 6, 0, 0); explanation.Visibility = Visibility.Collapsed; panel.Children.Add(explanation);
        ToolTip = "Hold Alt while moving into the controls";
        Child = panel;
    }

    private static Button Control(string shortcut, string title, Action action, TextBlock? key = null)
    {
        var button = new Button { FontFamily = Ui.Font, FontSize = 10, Foreground = Secondary,
            Background = ControlFill, BorderThickness = new Thickness(0), Padding = new Thickness(5, 3, 5, 3),
            Margin = new Thickness(0, 0, 6, 0), Cursor = System.Windows.Input.Cursors.Hand };
        var label = new StackPanel { Orientation = Orientation.Horizontal };
        if (shortcut.Length > 0)
        {
            key ??= Label(10);
            key.Text = shortcut; key.MinWidth = 8; key.Foreground = Secondary;
            key.Margin = new Thickness(0, 0, 4, 0); label.Children.Add(key);
        }
        var text = Label(10); text.Text = title; text.Foreground = Secondary;
        label.Children.Add(text); button.Content = label;
        var border = new FrameworkElementFactory(typeof(Border)); border.Name = "capsule";
        border.SetValue(Border.CornerRadiusProperty, new CornerRadius(4));
        border.SetBinding(Border.BackgroundProperty, new Binding("Background") { RelativeSource = RelativeSource.TemplatedParent });
        border.SetBinding(Border.PaddingProperty, new Binding("Padding") { RelativeSource = RelativeSource.TemplatedParent });
        var content = new FrameworkElementFactory(typeof(ContentPresenter));
        content.SetValue(FrameworkElement.HorizontalAlignmentProperty, HorizontalAlignment.Center);
        content.SetValue(FrameworkElement.VerticalAlignmentProperty, VerticalAlignment.Center); border.AppendChild(content);
        var template = new ControlTemplate(typeof(Button)) { VisualTree = border };
        var hover = new Trigger { Property = Button.IsMouseOverProperty, Value = true };
        hover.Setters.Add(new Setter(Border.BackgroundProperty, ActiveFill, "capsule")); template.Triggers.Add(hover);
        var focus = new Trigger { Property = Button.IsKeyboardFocusedProperty, Value = true };
        focus.Setters.Add(new Setter(Border.BackgroundProperty, ActiveFill, "capsule")); template.Triggers.Add(focus);
        button.Template = template;
        AutomationProperties.SetName(button, shortcut + " " + title);
        button.Click += (_, _) => Ui.Try(action);
        return button;
    }

    public void SetContent(HoveredText hit, string translation, string bridge, bool pinned, bool loading, bool isKnown, int level = 0, IReadOnlyList<BridgeToken>? explanationTokens = null, string meaningStatus = "")
    {
        translation = DanishLanguage.ConciseMeaning(translation, hit.Word.Text);
        bool directMeaning = !loading && translation.Length > 0 && ReadingPolicy.Key(translation) != ReadingPolicy.Key(hit.Word.Text);
        meaning.Text = directMeaning ? translation : loading ? "Looking up locally…" : "Local meaning unavailable";
        meaning.Visibility = Visibility.Visible;
        meaning.FontSize = directMeaning ? 16 : 11;
        meaning.Foreground = directMeaning ? Primary : Secondary;
        danish.Text = DanishLanguage.Display(hit.Word.Text);
        danish.FontSize = directMeaning ? 12 : 16;
        danish.FontWeight = directMeaning ? FontWeights.Medium : FontWeights.SemiBold;
        danish.Opacity = DanishLanguage.KnowledgeOpacity(level);
        explanation.SetTokens(explanationTokens ?? []); explanation.Visibility = explanationTokens is { Count: > 0 } ? Visibility.Visible : Visibility.Collapsed;
        knownState.Text = meaningStatus.Length > 0 ? (isKnown ? "Known · " : "") + meaningStatus : isKnown ? "Known" : "";
        knownState.ToolTip = meaningStatus == "Dictionary" ? "Word-only meaning. Enable local sentence meanings in Settings for context." : null;
        pin.Background = pinned ? ActiveFill : ControlFill;
    }
    public void SetFeedback(bool? markedKnown, bool animate = false)
    {
        feedback = markedKnown;
        knownKey.Text = markedKnown == true ? "✓" : shortcuts.Known.Display;
        unknownKey.Text = markedKnown == false ? "✓" : shortcuts.DontKnow.Display;
        known.Background = markedKnown == true ? ActiveFill : ControlFill;
        unknown.Background = markedKnown == false ? ActiveFill : ControlFill;
        if (markedKnown == true && animate && WindowsTheme.Current.Animate)
        {
            var scale = new ScaleTransform(1, 1); danish.RenderTransformOrigin = new Point(.5, .5); danish.RenderTransform = scale;
            var animation = new DoubleAnimationUsingKeyFrames();
            animation.KeyFrames.Add(new EasingDoubleKeyFrame(1.08, KeyTime.FromTimeSpan(TimeSpan.FromSeconds(.16))));
            animation.KeyFrames.Add(new EasingDoubleKeyFrame(1, KeyTime.FromTimeSpan(TimeSpan.FromSeconds(.5))));
            scale.BeginAnimation(ScaleTransform.ScaleXProperty, animation); scale.BeginAnimation(ScaleTransform.ScaleYProperty, animation);
        }
    }
    public void SetShortcuts(HotKeyConfiguration value)
    {
        if (shortcuts == value && known.ToolTip is not null) return;
        shortcuts = value;
        foreach (var pair in new[] { (knownKey, value.Known.Display), (unknownKey, value.DontKnow.Display), (pinKey, value.TogglePin.Display) })
        {
            double Width(string text) => new FormattedText(text, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, new Typeface(Ui.Font, FontStyles.Normal, FontWeights.Normal, FontStretches.Normal), 10, Secondary, VisualTreeHelper.GetDpi(this).PixelsPerDip).Width;
            pair.Item1.Width = Math.Ceiling(Math.Max(Width(pair.Item2), Width("✓")));
        }
        pinKey.Text = value.TogglePin.Display;
        known.ToolTip = "Mark known · " + value.Known.Display;
        unknown.ToolTip = "Restore English and save · " + value.DontKnow.Display;
        pin.ToolTip = "Keep this word open · " + value.TogglePin.Display;
        ToolTip = "Hold " + value.HoldModifier + " while moving into the controls";
        SetFeedback(feedback);
    }
}
