using Microsoft.Win32;
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Windows.Data;
using System.Windows;
using System.Windows.Media;

namespace Babelstaarnet.Windows;

// One palette per UI dispatcher. Existing controls keep the same brush objects
// when appearance changes, including popups outside the main visual tree.
internal sealed class WindowsTheme : INotifyPropertyChanged
{
    [ThreadStatic] private static WindowsTheme? current;
    internal static WindowsTheme Current => current ??= new();
    internal SolidColorBrush Ink { get; } = new();
    internal SolidColorBrush Muted { get; } = new();
    internal SolidColorBrush Paper { get; } = new();
    internal SolidColorBrush Surface { get; } = new();
    internal SolidColorBrush Stroke { get; } = new();
    internal SolidColorBrush Accent { get; } = new();
    internal SolidColorBrush OnAccent { get; } = new();
    internal SolidColorBrush AccentSoft { get; } = new();
    internal SolidColorBrush Hover { get; } = new();
    internal SolidColorBrush Control { get; } = new();
    internal SolidColorBrush EnglishTint { get; } = new();
    internal SolidColorBrush Focus { get; } = new();
    internal bool Dark { get; private set; }
    internal bool HighContrast { get; private set; }
    internal bool Animate => !HighContrast && SystemParameters.ClientAreaAnimation;
    internal string Preference { get; private set; } = "system";
    private readonly Dictionary<string, Color> colors = [];
    public event PropertyChangedEventHandler? PropertyChanged;
    public Color this[string key] => colors.GetValueOrDefault(key);
    private WindowsTheme()
    {
        // Bind the brushes so WPF template sealing cannot freeze the palette.
        // Updating the shared color source refreshes already-open surfaces.
        foreach (var pair in new Dictionary<string, SolidColorBrush>
        {
            [nameof(Ink)] = Ink, [nameof(Muted)] = Muted, [nameof(Paper)] = Paper, [nameof(Surface)] = Surface,
            [nameof(Stroke)] = Stroke, [nameof(Accent)] = Accent, [nameof(OnAccent)] = OnAccent,
            [nameof(AccentSoft)] = AccentSoft, [nameof(Hover)] = Hover, [nameof(Control)] = Control,
            [nameof(EnglishTint)] = EnglishTint, [nameof(Focus)] = Focus
        }) BindingOperations.SetBinding(pair.Value, SolidColorBrush.ColorProperty, new Binding("[" + pair.Key + "]") { Source = this, Mode = BindingMode.OneWay });
        Apply("system");
    }
    internal void Apply(string preference, bool? dark = null, bool? highContrast = null)
    {
        Preference = preference;
        HighContrast = highContrast ?? SystemParameters.HighContrast;
        Dark = dark ?? (preference == "dark" || preference == "system" &&
            (Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme", 1) as int?) == 0);
        Color C(string value) => (Color)ColorConverter.ConvertFromString(value);
        colors[nameof(Ink)] = HighContrast ? SystemColors.WindowTextColor : C(Dark ? "#F3F3F3" : "#1B1B1B");
        colors[nameof(Muted)] = HighContrast ? SystemColors.WindowTextColor : C(Dark ? "#BDBDBD" : "#606060");
        colors[nameof(Paper)] = HighContrast ? SystemColors.WindowColor : C(Dark ? "#202020" : "#F3F3F3");
        colors[nameof(Surface)] = HighContrast ? SystemColors.WindowColor : C(Dark ? "#2B2B2B" : "#FFFFFF");
        colors[nameof(Stroke)] = HighContrast ? SystemColors.WindowTextColor : C(Dark ? "#515151" : "#D6D6D6");
        Color accent = Dark ? SystemColors.AccentColorLight1 : SystemColors.AccentColorDark1;
        for (int i = 0; i < 16 && Contrast(accent, colors[nameof(Surface)]) < 4.5; i++) accent = Mix(accent, Dark ? Colors.White : Colors.Black, .12);
        colors[nameof(Accent)] = HighContrast ? SystemColors.HighlightColor : accent;
        colors[nameof(OnAccent)] = HighContrast ? SystemColors.HighlightTextColor : Contrast(Colors.White, accent) > Contrast(Colors.Black, accent) ? Colors.White : Colors.Black;
        colors[nameof(AccentSoft)] = HighContrast ? SystemColors.WindowColor : Mix(colors[nameof(Surface)], accent, Dark ? .18 : .1);
        colors[nameof(Hover)] = HighContrast ? SystemColors.WindowColor : C(Dark ? "#383838" : "#F2F2F2");
        colors[nameof(Control)] = HighContrast ? SystemColors.WindowColor : C(Dark ? "#343434" : "#F5F5F5");
        colors[nameof(EnglishTint)] = HighContrast ? SystemColors.WindowColor : C(Dark ? "#454545" : "#EDEDED");
        colors[nameof(Focus)] = HighContrast ? SystemColors.HighlightColor : colors[nameof(Accent)];
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs("Item[]"));
    }
    private static Color Mix(Color a, Color b, double amount) => Color.FromRgb((byte)Math.Round(a.R * (1 - amount) + b.R * amount), (byte)Math.Round(a.G * (1 - amount) + b.G * amount), (byte)Math.Round(a.B * (1 - amount) + b.B * amount));
    private static double Contrast(Color a, Color b)
    {
        double L(Color c) { double S(byte value) { double n = value / 255.0; return n <= .04045 ? n / 12.92 : Math.Pow((n + .055) / 1.055, 2.4); } return .2126 * S(c.R) + .7152 * S(c.G) + .0722 * S(c.B); }
        double x = L(a), y = L(b); return (Math.Max(x, y) + .05) / (Math.Min(x, y) + .05);
    }
    internal void AddResources(ResourceDictionary resources)
    {
        foreach (var pair in new Dictionary<string, Brush>
        {
            ["Ink"] = Ink, ["Muted"] = Muted, ["Paper"] = Paper, ["Surface"] = Surface,
            ["Stroke"] = Stroke, ["Accent"] = Accent, ["OnAccent"] = OnAccent,
            ["AccentSoft"] = AccentSoft, ["Hover"] = Hover, ["Control"] = Control
        }) resources["Babel." + pair.Key] = pair.Value;
    }
    internal void Attach(Window window)
    {
        AddResources(window.Resources);
        ApplyNative(window);
    }
    internal void ApplyNative(Window window)
    {
        if (window.AllowsTransparency) return;
#pragma warning disable WPF0001 // Built-in Fluent API, scoped to the native host.
        window.ThemeMode = Preference switch { "light" => ThemeMode.Light, "dark" => ThemeMode.Dark, _ => ThemeMode.System };
#pragma warning restore WPF0001
    }
}
