using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Threading;
using Forms = System.Windows.Forms;

namespace Babelstaarnet.Windows;

internal sealed class NewsPopupPanel : Border
{
    internal NewsReadingSupport Reader { get; }
    internal NewsPopupPanel(NewsService news, NewsPopupItem item, Action close, Action openBook)
    {
        Reader = news.MakePopupReader();
        Background = Ui.Paper; Padding = new Thickness(16);
        var body = new DockPanel(); Child = body;
        var top = new StackPanel(); DockPanel.SetDock(top, Dock.Top); body.Children.Add(top);
        var heading = new DockPanel(); var x = Ui.Button("Close", close); DockPanel.SetDock(x, Dock.Right); heading.Children.Add(x); heading.Children.Add(Ui.Text("A little Danish", 18, true)); top.Children.Add(heading);
        var note = Ui.Text("DR news · internet source · adapted locally", 11); note.Foreground = Ui.Muted; note.ToolTip = "Local model: " + item.Model; top.Children.Add(note);
        var footer = new StackPanel { Margin = new Thickness(0, 8, 0, 0) }; DockPanel.SetDock(footer, Dock.Bottom); body.Children.Add(footer);
        var actions = new WrapPanel(); actions.Children.Add(Ui.Button("Pause today", () => { news.PausePopupsForToday(true); close(); })); actions.Children.Add(Ui.Button("Turn off", () => { news.ConfigurePopups(false, news.PopupPreferences.IntervalMinutes); close(); })); actions.Children.Add(Ui.Button("Open Word Book", openBook)); footer.Children.Add(actions);
        var content = new StackPanel(); var card = new NewsReadingCard(news, new(item.Adapted, [], 0), compact: true, reader: Reader); content.Children.Add(card);
        var original = new Expander { Header = "Original DR headline", Content = Ui.Text(item.Original.Title, 12), Foreground = Ui.Ink, FontFamily = Ui.Font, FontSize = 11, Margin = new Thickness(0, 10, 0, 5) }; content.Children.Add(original);
        var listen = Ui.Button("Listen", () => Reader.Speak?.Invoke(item.Text)); listen.IsEnabled = Reader.Speak is not null; content.Children.Add(listen);
        body.Children.Add(new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Content = content });
        Loaded += async (_, _) => { Reader.Changed += card.UpdateSupport; await Reader.PrepareAsync(item.Adapted); };
        Unloaded += (_, _) => Reader.Changed -= card.UpdateSupport;
    }
}

internal sealed class NewsPopupWindow : Window
{
    private readonly NewsService news;
    private readonly NewsPopupItem item;
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(1) };
    private DateTime lastInteraction = DateTime.UtcNow;
    internal NewsPopupWindow(NewsService news, NewsPopupItem item, Action openBook)
    {
        this.news = news; this.item = item;
        Title = "Babelstårnet · A little Danish"; Icon = BrandIcons.AppImage;
        Width = 460; Height = 400; ShowActivated = false; ShowInTaskbar = false; Topmost = true;
        WindowStyle = WindowStyle.ToolWindow; ResizeMode = ResizeMode.NoResize;
        var panel = new NewsPopupPanel(news, item, Close, () => { Close(); openBook(); }); Content = panel; WindowsTheme.Current.Attach(this);
        PreviewKeyDown += (_, e) => { if (e.Key == Key.Escape) { e.Handled = true; Close(); } };
        timer.Tick += (_, _) =>
        {
            if ((!item.Preview && !news.PopupPreferences.Enabled) || !news.Preferences.Enabled || (!item.Preview && news.PopupsPaused)) { Close(); return; }
            if (IsMouseOver || IsKeyboardFocusWithin) lastInteraction = DateTime.UtcNow;
            else if (DateTime.UtcNow - lastInteraction >= TimeSpan.FromSeconds(45)) Close();
        };
        Closed += (_, _) => { timer.Stop(); news.PopupVisible = false; panel.Reader.Dispose(); };
    }
    internal void ShowCard()
    {
        var area = Forms.Screen.FromPoint(Forms.Cursor.Position).WorkingArea;
        var handle = new WindowInteropHelper(this).EnsureHandle(); NativeMethods.SetWindowPos(handle, IntPtr.Zero, area.Right - 1, area.Top + 1, 0, 0, 0x15);
        double scale = NativeMethods.GetDpiForWindow(handle) / 96.0;
        Height = Math.Min(400, area.Height / scale - 36); Width = Math.Min(460, area.Width / scale - 36);
        int width = (int)Math.Ceiling(Width * scale), height = (int)Math.Ceiling(Height * scale);
        news.PopupVisible = true; Show();
        NativeMethods.SetWindowPos(handle, new IntPtr(-1), area.Right - width - 18, area.Bottom - height - 18, width, height, 0x50);
        lastInteraction = DateTime.UtcNow; timer.Start();
    }
}
