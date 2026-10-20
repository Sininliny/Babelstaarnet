using System;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Media;
using System.Windows.Shapes;

namespace Babelstaarnet.Windows;

internal static class Ui
{
    public static readonly Brush Ink = ColorBrush(35, 35, 39);
    public static readonly Brush Muted = ColorBrush(112, 112, 120);
    public static readonly Brush Paper = ColorBrush(243, 243, 246);
    public static readonly Brush Surface = Brushes.White;
    public static readonly Brush Stroke = ColorBrush(218, 218, 224);
    public static readonly Brush Accent = ColorBrush(48, 115, 220);
    public static readonly Brush AccentSoft = ColorBrush(234, 240, 252);
    public static readonly FontFamily Font = new("Segoe UI Variable Text, Segoe UI");
    public static Brush ColorBrush(byte r, byte g, byte b)
    { var brush = new SolidColorBrush(Color.FromRgb(r, g, b)); brush.Freeze(); return brush; }

    public static TextBlock Text(string text, double size = 14, bool bold = false) => new()
    {
        Text = text, FontSize = size, FontFamily = Font, Foreground = Ink, TextWrapping = TextWrapping.Wrap,
        FontWeight = bold ? FontWeights.SemiBold : FontWeights.Normal, Margin = new Thickness(0, 0, 0, 10)
    };

    public static Button Button(string title, Action action)
    {
        var button = ActionButton(title, action);
        button.Margin = new Thickness(0, 0, 8, 8);
        return button;
    }

    public static Button ActionButton(string title, Action action, bool primary = false)
    {
        var button = new Button
        {
            Content = title, FontFamily = Font, FontSize = 12, FontWeight = FontWeights.SemiBold,
            Padding = new Thickness(12, 8, 12, 8), MinHeight = 34,
            Background = primary ? Accent : Surface, Foreground = primary ? Brushes.White : Ink,
            BorderBrush = primary ? Accent : Stroke, BorderThickness = new Thickness(1),
            Cursor = System.Windows.Input.Cursors.Hand, Focusable = true
        };
        var border = new FrameworkElementFactory(typeof(Border));
        border.Name = "surface";
        border.SetValue(Border.CornerRadiusProperty, new CornerRadius(8));
        foreach (var property in new[] { Border.BackgroundProperty, Border.BorderBrushProperty, Border.BorderThicknessProperty, Border.PaddingProperty })
            border.SetBinding(property, new Binding(property.Name) { RelativeSource = RelativeSource.TemplatedParent });
        var presenter = new FrameworkElementFactory(typeof(ContentPresenter));
        presenter.SetBinding(FrameworkElement.HorizontalAlignmentProperty, new Binding("HorizontalContentAlignment") { RelativeSource = RelativeSource.TemplatedParent });
        presenter.SetValue(FrameworkElement.VerticalAlignmentProperty, VerticalAlignment.Center);
        border.AppendChild(presenter);
        var template = new ControlTemplate(typeof(Button)) { VisualTree = border };
        var hover = new Trigger { Property = System.Windows.Controls.Button.IsMouseOverProperty, Value = true };
        hover.Setters.Add(new Setter(Border.BackgroundProperty, primary ? ColorBrush(36, 91, 181) : AccentSoft, "surface"));
        template.Triggers.Add(hover);
        var focus = new Trigger { Property = System.Windows.Controls.Button.IsKeyboardFocusedProperty, Value = true };
        focus.Setters.Add(new Setter(Border.BorderBrushProperty, Accent, "surface"));
        focus.Setters.Add(new Setter(Border.BorderThicknessProperty, new Thickness(2), "surface"));
        template.Triggers.Add(focus);
        var disabled = new Trigger { Property = System.Windows.Controls.Button.IsEnabledProperty, Value = false };
        disabled.Setters.Add(new Setter(UIElement.OpacityProperty, 0.45));
        template.Triggers.Add(disabled);
        button.Template = template;
        AutomationProperties.SetName(button, title);
        button.Click += (_, _) => Try(action);
        return button;
    }

    public static FrameworkElement Icon(string name, Brush? brush = null, double size = 16)
    {
        string shape = name switch
        {
            "speaker" => "M3,9 L7,9 12,5 12,19 7,15 3,15 Z M16,8 C19,10 19,14 16,16 M19,5 C24,9 24,15 19,19",
            "pin" => "M8,3 L16,3 M9,3 L9,9 6,13 18,13 15,9 15,3 M12,13 L12,21",
            "check" => "M5,12 L10,17 20,7",
            "plus" => "M12,5 L12,19 M5,12 L19,12",
            _ => "M5,12 L19,12"
        };
        return new Viewbox { Width = size, Height = size, Child = new Path
        { Width = 24, Height = 24, Data = Geometry.Parse(shape), Stroke = brush ?? Ink, StrokeThickness = 1.7,
            StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round, StrokeLineJoin = PenLineJoin.Round } };
    }

    public static void Try(Action action)
    {
        try { action(); }
        catch (Exception error) { Error(error.Message); }
    }
    public static void Error(string message) => MessageBox.Show(message, "Babelstårnet", MessageBoxButton.OK, MessageBoxImage.Information);
}
