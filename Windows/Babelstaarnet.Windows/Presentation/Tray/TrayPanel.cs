using System;
using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using Forms = System.Windows.Forms;

namespace Babelstaarnet.Windows;

internal sealed class TrayPanel : Border
{
    private readonly ReaderUiModel model;
    private readonly TextBlock status = Ui.Text("", 11), toggleTitle = Ui.Text("", 12, true), toggleDetail = Ui.Text("", 11);
    private readonly TextBlock shortcut = Ui.Text("", 11), hints = Ui.Text("", 10), failure = Ui.Text("", 11);
    private readonly Button start, retry, book;
    private readonly CheckBox word = new() { Content = "Word meaning" }, sentence = new() { Content = "Whole sentence" };
    private bool refreshing;
    private readonly Image headerLogo = new();
    public TrayPanel(ReaderUiModel model)
    {
        this.model = model; Width = 290; Padding = new Thickness(14); Background = Ui.Surface; CornerRadius = new CornerRadius(12); BorderThickness = new Thickness(.7); BorderBrush = Ui.Stroke;
        System.Windows.Documents.TextElement.SetFontFamily(this, Ui.Font); var panel = new StackPanel(); Child = panel;
        var header = new DockPanel(); var image = headerLogo; image.Width = image.Height = 26; image.Margin = new Thickness(0, 0, 9, 0);
        header.Children.Add(image); var name = new StackPanel(); var title = Ui.Text("Babelstårnet", 14, true); title.Margin = new Thickness(0, 0, 0, 2); name.Children.Add(title); status.Margin = new Thickness(0); status.Foreground = Ui.Muted; name.Children.Add(status); header.Children.Add(name); panel.Children.Add(header);
        book = Ui.ActionButton("Word Book", model.OpenBook); book.FontSize = 13; book.FontWeight = FontWeights.SemiBold; book.HorizontalContentAlignment = HorizontalAlignment.Left; book.Margin = new Thickness(0, 13, 0, 0);
        System.Windows.Automation.AutomationProperties.SetName(book, "Open Word Book"); panel.Children.Add(book);
        var news = Ui.ActionButton("Read something new", model.OpenNews); news.HorizontalContentAlignment = HorizontalAlignment.Left; news.Margin = new Thickness(0, 5, 0, 0); panel.Children.Add(news);
        var cards = Ui.ActionButton("Scheduled news cards…", model.OpenNewsSettings); cards.HorizontalContentAlignment = HorizontalAlignment.Left; cards.FontSize = 11; cards.Foreground = Ui.Muted; cards.Margin = new Thickness(0, 5, 0, 0); panel.Children.Add(cards);
        var startContent = new StackPanel { HorizontalAlignment = HorizontalAlignment.Left }; toggleTitle.Margin = new Thickness(0, 0, 0, 3); toggleDetail.Margin = new Thickness(0); toggleDetail.Foreground = Ui.Muted; startContent.Children.Add(toggleTitle); startContent.Children.Add(toggleDetail);
        start = Ui.ActionButton("", model.Toggle); start.Content = startContent; start.HorizontalContentAlignment = HorizontalAlignment.Stretch; start.Margin = new Thickness(0, 13, 0, 9); panel.Children.Add(start);
        failure.Foreground = Ui.ColorBrush(160, 54, 43); failure.MaxHeight = 48; failure.TextTrimming = TextTrimming.CharacterEllipsis; failure.Margin = new Thickness(0, 2, 0, 5); panel.Children.Add(failure); retry = Ui.Button("Retry", model.CheckEngines); panel.Children.Add(retry);
        var hoverRow = new DockPanel { Margin = new Thickness(0, 4, 0, 0) }; shortcut.TextAlignment = TextAlignment.Right; shortcut.Foreground = Ui.Muted; DockPanel.SetDock(shortcut, Dock.Right); hoverRow.Children.Add(shortcut); hoverRow.Children.Add(Ui.Text("Hover translation", 12, true)); panel.Children.Add(hoverRow);
        var detail = Ui.Text("Keep reading " + model.ActiveLanguages.Source.Name + ". " + model.ActiveLanguages.Target.Name + " helps when needed.", 11); detail.Foreground = Ui.Muted; panel.Children.Add(detail);
        foreach (var check in new[] { word, sentence }) { FormControls.Apply(check); check.FontSize = 12; check.Margin = new Thickness(0, 4, 0, 6); panel.Children.Add(check); check.Click += (_, _) => { if (refreshing) return; model.Preferences.WordMeaning = word.IsChecked == true; model.Preferences.WholeSentence = sentence.IsChecked == true; model.Commit(); }; }
        hints.Foreground = Ui.Muted; hints.Margin = new Thickness(0, 6, 0, 11); panel.Children.Add(hints);
        panel.Children.Add(new Border { Height = .7, Background = Ui.Stroke, Margin = new Thickness(0, 0, 0, 9) });
        var bottom = new Grid(); bottom.ColumnDefinitions.Add(new ColumnDefinition()); bottom.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto }); bottom.Children.Add(Footer("Settings…", model.OpenSettings)); var quit = Footer("Quit", model.Quit); Grid.SetColumn(quit, 1); bottom.Children.Add(quit); panel.Children.Add(bottom);
        Loaded += (_, _) => { model.Changed += Refresh; Refresh(); }; Unloaded += (_, _) => model.Changed -= Refresh; Refresh();
    }
    private static Button Footer(string text, Action action)
    { var button = Ui.ActionButton(text, action); button.Background = Brushes.Transparent; button.BorderThickness = new Thickness(0); button.FontSize = 11; button.MinHeight = 27; button.Padding = new Thickness(5); button.HorizontalContentAlignment = HorizontalAlignment.Left; return button; }
    private void Refresh()
    {
        refreshing = true;
        headerLogo.Source = BrandIcons.Image(WindowsTheme.Current.Dark ? "tray-active-dark.ico" : "tray-active-light.ico");
        status.Text = model.Installing ? "Installing local resources…" : model.Busy ? "Preparing local engines…" : model.Idle ? "Idle · waiting for input" : model.Active ? "Active" : "Inactive";
        toggleTitle.Text = model.Active ? "Stop translating" : "Start translating"; toggleDetail.Text = model.Active ? "Pause reading assistance" : "Hover a word to begin";
        start.IsEnabled = !model.Installing; shortcut.Text = model.Preferences.Shortcuts.ToggleLearning.Display;
        word.IsChecked = model.Preferences.WordMeaning; sentence.IsChecked = model.Preferences.WholeSentence;
        var keys = model.Preferences.Shortcuts; hints.Text = $"{keys.Known.Display}  Knew   ·   {keys.DontKnow.Display}  Don’t know   ·   {keys.TogglePin.Display}  Pin\nHold {keys.HoldModifier} to move into a bubble.";
        failure.Text = model.Failure ?? ""; failure.ToolTip = model.Failure; failure.Visibility = retry.Visibility = model.Failure is null ? Visibility.Collapsed : Visibility.Visible; retry.IsEnabled = !model.Busy && !model.Installing;
        book.Content = model.BookTitle; refreshing = false;
    }
}

internal sealed class TrayPopup : Window
{
    private bool closing, closed;
    public TrayPopup(ReaderUiModel model)
    {
        Title = "Babelstårnet"; Content = new Border { Padding = new Thickness(18), Child = new FloatingSurface(new TrayPanel(model)) }; Background = Brushes.Transparent; AllowsTransparency = true; WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize; ShowInTaskbar = false; Topmost = true;
        Deactivated += (_, _) => Dismiss(); PreviewKeyDown += (_, e) => { if (e.Key == Key.Escape) { e.Handled = true; Dismiss(); } };
        SourceInitialized += (_, _) => { var handle = new WindowInteropHelper(this).Handle; long style = NativeMethods.GetWindowLongPtr(handle, -20).ToInt64(); NativeMethods.SetWindowLongPtr(handle, -20, new IntPtr(style | 0x80)); };
    }
    public void Dismiss()
    {
        if (!closing && !closed) Close();
    }
    protected override void OnClosing(CancelEventArgs e)
    {
        // Destroying an active HWND raises Deactivated synchronously. Set the
        // guard before any handlers or native teardown can request Close again.
        closing = true;
        base.OnClosing(e);
        if (e.Cancel) closing = false;
    }
    protected override void OnClosed(EventArgs e)
    { closed = true; base.OnClosed(e); }
    internal Size MeasurePopup()
    { var content = (FrameworkElement)Content; content.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity)); return content.DesiredSize; }
    public void OpenAtCursor()
    {
        if (!NativeMethods.GetCursorPos(out var point)) { Show(); return; }
        var work = Forms.Screen.FromPoint(new System.Drawing.Point(point.X, point.Y)).WorkingArea;
        var handle = new WindowInteropHelper(this).EnsureHandle(); NativeMethods.SetWindowPos(handle, new IntPtr(-1), point.X, point.Y, 0, 0, 0x11);
        double scale = NativeMethods.GetDpiForWindow(handle) / 96.0;
        var size = MeasurePopup(); Width = size.Width; Height = size.Height;
        int width = (int)Math.Ceiling(size.Width * scale), height = (int)Math.Ceiling(size.Height * scale);
        int x = Math.Clamp(point.X - width / 2, work.Left, Math.Max(work.Left, work.Right - width)); int y = Math.Clamp(point.Y - height, work.Top, Math.Max(work.Top, work.Bottom - height));
        Left = x / scale; Top = y / scale; Show(); NativeMethods.SetWindowPos(handle, new IntPtr(-1), x, y, width, height, 0x40); Activate();
    }
}
