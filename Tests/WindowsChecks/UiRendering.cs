using Babelstaarnet.Core;
using Babelstaarnet.Windows;
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;

internal static class UiRendering
{
    internal static int Run(string output)
    {
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            try
            {
                WindowsTheme.Current.Apply("light", dark: false, highContrast: false);
                Render(output, known: false, loading: false);
                Render(Path.Combine(Path.GetDirectoryName(output)!, Path.GetFileNameWithoutExtension(output) + "-known.png"), known: true, loading: false);
                Render(Path.Combine(Path.GetDirectoryName(output)!, Path.GetFileNameWithoutExtension(output) + "-loading.png"), known: false, loading: true);
                RenderApplication(output);
                string dark = Path.Combine(Path.GetDirectoryName(output)!, Path.GetFileNameWithoutExtension(output) + "-dark.png");
                WindowsTheme.Current.Apply("dark", dark: true, highContrast: false); Render(dark, known: false, loading: false); RenderApplication(dark);
            }
            catch (Exception error) { failure = error; }
        });
        thread.SetApartmentState(ApartmentState.STA); thread.Start(); thread.Join();
        if (failure is not null) throw failure;
        Console.WriteLine("Rendered production word and sentence panels: " + Path.GetFullPath(output));
        return 0;
    }
    private static void Save(FrameworkElement element, string output, int width, int height)
    {
        element.Measure(new Size(width, height)); element.Arrange(new Rect(0, 0, width, height)); element.UpdateLayout();
        var bitmap = new RenderTargetBitmap(width * 2, height * 2, 192, 192, PixelFormats.Pbgra32); bitmap.Render(element);
        var png = new PngBitmapEncoder(); png.Frames.Add(BitmapFrame.Create(bitmap)); using var stream = File.Create(output); png.Save(stream);
    }
    private static void RenderApplication(string output)
    {
        string stem = Path.Combine(Path.GetDirectoryName(Path.GetFullPath(output))!, Path.GetFileNameWithoutExtension(output));
        string fixture = Path.Combine(Path.GetDirectoryName(Path.GetFullPath(output))!, "ui-render-fixture"); Directory.CreateDirectory(fixture);
        string file = Path.Combine(fixture, "vocabulary.json"); if (File.Exists(file)) File.Delete(file);
        var now = DateTimeOffset.Now; var store = new VocabularyStore(file);
        store.Save("tilbageholde", "detain", "Le Pen truer med at tilbageholde milliarder i EU-bidrag.", now.AddDays(-3)); store.Observe("tilbageholde", "Le Pen truer med at tilbageholde milliarder i EU-bidrag.", now);
        store.Save("anspændte", "tense", "Mette Frederiksen om den anspændte situation.", now.AddDays(-2));
        store.Save("æbler", "apples", "Jeg spiser æbler.", now.AddDays(-1)); store.Mark("æbler", true, now);
        var preferences = new ReaderPreferences(); var model = new ReaderUiModel(preferences, store, Path.Combine(fixture, "preferences.json")) { Active = true, OcrReady = true, TranslationReady = true, VoiceReady = true };
        Save(new SettingsShell(model), stem + "-settings-shell.png", 880, 640);
        var settings = new SettingsPanel(model); settings.Measure(new Size(480, 3000)); settings.Arrange(new Rect(0, 0, 480, 3000)); settings.UpdateLayout();
        // Render the actual grouped form without the viewport cropping its lower sections.
        var form = (FrameworkElement)settings.Content; settings.Content = null; form.Measure(new Size(480, double.PositiveInfinity)); int formHeight = (int)Math.Ceiling(form.DesiredSize.Height);
        Save(new Border { Width = 480, Background = Ui.Paper, Child = form }, stem + "-settings.png", 480, formHeight);
        var tray = new TrayPanel(model); tray.Measure(new Size(290, double.PositiveInfinity)); Save(tray, stem + "-tray.png", 290, (int)Math.Ceiling(tray.DesiredSize.Height));
        var book = new WordBookPanel(store, _ => { }, preferences); Save(book, stem + "-book.png", 820, 500);
        book.BeginReview(); book.Reveal(); Save(book, stem + "-review.png", 820, 500);
        var icons = new StackPanel { Orientation = Orientation.Horizontal, Background = Brushes.White };
        foreach (var state in new[] { "inactive", "active" })
            foreach (var theme in new[] { "light", "dark" })
                icons.Children.Add(new Border { Width = 84, Height = 72, Background = theme == "light" ? Brushes.White : Ui.ColorBrush(31, 31, 35), Child = new Image { Source = BrandIcons.Image($"tray-{state}-{theme}.ico"), Width = 32, Height = 32 } });
        Save(icons, stem + "-icons.png", 336, 72);
    }
    private static void Render(string output, bool known, bool loading)
    {
        const int width = 960, height = 590;
        var canvas = new Canvas { Width = width, Height = height, Background = Ui.ColorBrush(232, 233, 234) };
        void Add(UIElement element, double x, double y) { Canvas.SetLeft(element, x); Canvas.SetTop(element, y); canvas.Children.Add(element); }
        var paper = new Border { Width = 850, Height = 340, CornerRadius = new CornerRadius(12), Background = Brushes.White, BorderBrush = Ui.ColorBrush(216, 217, 219), BorderThickness = new Thickness(1) };
        Add(paper, 55, 135);
        TextBlock Text(string value, double size = 14, bool bold = false) => new() { Text = value, FontFamily = Ui.Font, FontSize = size, FontWeight = bold ? FontWeights.SemiBold : FontWeights.Normal, Foreground = Ui.ColorBrush(27, 27, 27) };
        Add(Text("Vejledning til ansøgere", 18, true), 85, 170);
        Add(Text("Sagsbehandlingen begynder, når alle oplysninger er modtaget."), 85, 220);
        const string source = "Ansøgningen skal indgives senest fire uger efter refleksionsperioden udløber.";
        var sourceText = Text(source); Add(sourceText, 85, 260);
        Add(Text("Fristen kan ikke forlænges."), 85, 300);
        var foot = Text("Se afsnit 4 om klageadgang."); foot.Foreground = Ui.Muted; Add(foot, 85, 340);
        double Length(string text) => new FormattedText(text, CultureInfo.GetCultureInfo("da-DK"), FlowDirection.LeftToRight,
            new Typeface(Ui.Font, FontStyles.Normal, FontWeights.Normal, FontStretches.Normal), 14, Brushes.Black, 1).WidthIncludingTrailingWhitespace;
        var words = ReadingPolicy.Words().Matches(source).Select(m => new RecognizedWord(m.Value,
            new(85 + (int)Math.Round(Length(source[..m.Index])), 260, (int)Math.Ceiling(Length(m.Value)), 20))).ToArray();
        var focus = words.Single(w => w.Text == "refleksionsperioden");
        var hit = new HoveredText(focus, new(source, words));
        var glosses = new Dictionary<string, string> { ["ansoegningen"] = "The application", ["indgives"] = "be submitted", ["refleksionsperioden"] = "the period of reflection", ["udloeber"] = "expires" };
        var tokens = BridgePresentation.Tokens(hit, loading ? new Dictionary<string, string>() : glosses,
            key => known && key == "refleksionsperioden");
        var word = new OverlayCard(); word.SetContent(hit, "the period of reflection", "", true, loading, known);
        if (known) word.SetFeedback(true);
        var sentence = new SentenceCard(); sentence.SetContent(tokens);
        word.Measure(new Size(280, double.PositiveInfinity)); sentence.Measure(new Size(420, double.PositiveInfinity));
        var frames = OverlayLayout.Place(focus.Bounds, OverlayLayout.SourceFrame(hit), new(280, (int)Math.Ceiling(word.DesiredSize.Height)), new(420, (int)Math.Ceiling(sentence.DesiredSize.Height)), new(0, 0, width, height)) ?? throw new Exception("No safe paired layout.");
        Add(new FloatingSurface(word), frames.Word.X, frames.Word.Y); Add(new FloatingSurface(sentence), frames.Sentence.X, frames.Sentence.Y);
        var rule = OverlayLayout.FocusRule(focus.Bounds);
        Add(new Border { Width = rule.Width, Height = rule.Height, CornerRadius = new CornerRadius(1), Background = Ui.Accent }, rule.X, rule.Y);
        canvas.Measure(new Size(width, height)); canvas.Arrange(new Rect(0, 0, width, height)); canvas.UpdateLayout();
        if (word.ActualWidth != 280 || sentence.ActualWidth != 420) throw new Exception("Mac panel dimensions changed.");
        var image = new RenderTargetBitmap(width * 2, height * 2, 192, 192, PixelFormats.Pbgra32); image.Render(canvas);
        var png = new PngBitmapEncoder(); png.Frames.Add(BitmapFrame.Create(image));
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(output))!);
        using var file = File.Create(output); png.Save(file);
    }
}
