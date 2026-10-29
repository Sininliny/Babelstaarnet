using System;
using System.Drawing;
using Forms = System.Windows.Forms;

namespace Babelstaarnet.Windows;

// Notification-area keyboard/context activation bridge into the themed WPF popup.
internal sealed class TrayMenu : Forms.ContextMenuStrip
{
    private readonly ReaderUiModel model;
    private readonly Forms.ToolStripMenuItem book, toggle;
    internal TrayMenu(ReaderUiModel model, Action openPanel)
    {
        this.model = model; Renderer = new Forms.ToolStripSystemRenderer();
        book = Add("Word Book", "word-book", model.OpenBook);
        Add("Read something new", "news", model.OpenNews);
        Add("Scheduled news cards…", "news-cards", model.OpenNewsSettings);
        Items.Add(new Forms.ToolStripSeparator());
        toggle = Add("Start translating", "toggle-reading", model.Toggle);
        Add("Reading controls…", "reading-controls", model.OpenReadingControls);
        Items.Add(new Forms.ToolStripSeparator());
        Add("Settings…", "settings", model.OpenSettings); Add("Quit", "quit", model.Quit);
        // NotifyIcon routes right-click and keyboard context activation here.
        // The app opens the same themed surface used by a primary click.
        Opening += (_, e) => { e.Cancel = true; RefreshMenu(); Ui.Try(openPanel); }; RefreshMenu();
    }
    private Forms.ToolStripMenuItem Add(string text, string name, Action action)
    {
        var item = new Forms.ToolStripMenuItem(text) { Name = name }; item.Click += (_, _) => Ui.Try(action); Items.Add(item); return item;
    }
    private void RefreshMenu()
    {
        var theme = WindowsTheme.Current; BackColor = Color.FromArgb(theme.Surface.Color.R, theme.Surface.Color.G, theme.Surface.Color.B); ForeColor = Color.FromArgb(theme.Ink.Color.R, theme.Ink.Color.G, theme.Ink.Color.B);
        book.Text = model.BookTitle; toggle.Text = model.Active ? "Stop translating" : "Start translating"; toggle.Enabled = !model.Installing;
    }
}
