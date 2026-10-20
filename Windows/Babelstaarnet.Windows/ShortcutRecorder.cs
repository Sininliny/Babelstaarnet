using Babelstaarnet.Core;
using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace Babelstaarnet.Windows;

internal sealed class ShortcutRecorder : Button
{
    private readonly ReaderUiModel model;
    private readonly ShortcutAction action;
    private bool recording;
    public ShortcutRecorder(ReaderUiModel model, ShortcutAction action)
    {
        this.model = model; this.action = action;
        Width = 145; Height = 27; FontFamily = Ui.Font; FontSize = 12;
        Template = Ui.ActionButton("", () => { }).Template;
        Content = model.Preferences.Shortcuts.For(action).Display;
        Background = Ui.Surface; BorderBrush = Ui.Stroke; Padding = new Thickness(6, 2, 6, 2);
        ToolTip = "Click, then press a replacement shortcut. Esc cancels.";
        Click += (_, _) => { if (recording) return; model.ShortcutCapture(true); recording = true; Content = "Press shortcut…"; Focus(); };
        LostKeyboardFocus += (_, _) => Cancel();
        PreviewKeyDown += Record;
        Unloaded += (_, _) => Cancel();
    }
    private void Record(object sender, KeyEventArgs e)
    {
        if (!recording) return;
        e.Handled = true; var key = e.Key == Key.System ? e.SystemKey : e.Key;
        if (key == Key.Escape) { Cancel(); return; }
        if (key is Key.LeftCtrl or Key.RightCtrl or Key.LeftAlt or Key.RightAlt or Key.LeftShift or Key.RightShift or Key.LWin or Key.RWin) return;
        uint modifiers = 0;
        if ((Keyboard.Modifiers & ModifierKeys.Alt) != 0) modifiers |= 1;
        if ((Keyboard.Modifiers & ModifierKeys.Control) != 0) modifiers |= 2;
        if ((Keyboard.Modifiers & ModifierKeys.Shift) != 0) modifiers |= 4;
        if ((Keyboard.Modifiers & ModifierKeys.Windows) != 0) modifiers |= 8;
        var next = model.Preferences.Shortcuts.With(action, new((uint)KeyInterop.VirtualKeyFromKey(key), modifiers));
        string? error = next.ValidationError();
        if (error is null) error = model.ChangeShortcuts(next);
        model.ShortcutMessage = error;
        Cancel(); model.Notify();
    }
    public void Refresh() { if (!recording) Content = model.Preferences.Shortcuts.For(action).Display; }
    private void Cancel()
    {
        if (!recording) return; recording = false; model.ShortcutCapture(false); Refresh();
    }
}
