using Babelstaarnet.Core;
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Windows.Interop;

namespace Babelstaarnet.Windows;

internal sealed class HotKeyService : IDisposable
{
    private readonly HwndSource source;
    private readonly HashSet<int> registered = [];
    private HotKeyConfiguration configuration = HotKeyConfiguration.Defaults;
    private bool feedback, suspended;
    public event Action<int>? Pressed;
    public HotKeyService()
    {
        source = new HwndSource(new HwndSourceParameters("Babelstaarnet hotkeys") { ParentWindow = new IntPtr(-3), Width = 0, Height = 0, WindowStyle = 0 });
        source.AddHook(HandleMessage);
    }
    public void Configure(HotKeyConfiguration next)
    {
        if (next.ValidationError() is { } error) throw new InvalidOperationException(error);
        var previous = configuration;
        bool wasSuspended = suspended;
        suspended = false;
        UnregisterAll(); configuration = next;
        try { RegisterCurrent(); if (wasSuspended) UnregisterAll(); }
        catch
        {
            UnregisterAll(); configuration = previous;
            if (!wasSuspended) { try { RegisterCurrent(); } catch { UnregisterAll(); } }
            throw;
        }
        finally { suspended = wasSuspended; }
    }
    public void Suspend(bool value)
    {
        suspended = value; UnregisterAll(); if (!value) RegisterCurrent();
    }
    private void Register(ShortcutAction action)
    {
        var shortcut = configuration.For(action);
        if (!NativeMethods.RegisterHotKey(source.Handle, (int)action, 0x4000 | shortcut.Modifiers, shortcut.Key))
            throw new Win32Exception(System.Runtime.InteropServices.Marshal.GetLastWin32Error(), shortcut.Display + " is already used by another app.");
        registered.Add((int)action);
    }
    private void RegisterCurrent()
    {
        if (suspended) return;
        Register(ShortcutAction.ToggleLearning);
        if (feedback) foreach (var action in new[] { ShortcutAction.Known, ShortcutAction.DontKnow, ShortcutAction.TogglePin, ShortcutAction.SentenceMeaning }) Register(action);
    }
    public void EnableFeedback(bool enabled)
    {
        if (feedback == enabled) return;
        feedback = enabled;
        if (!enabled)
            foreach (int id in new[] { 2, 3, 4, 5 }) { if (registered.Remove(id)) NativeMethods.UnregisterHotKey(source.Handle, id); }
        else if (!suspended)
        {
            try { foreach (var a in new[] { ShortcutAction.Known, ShortcutAction.DontKnow, ShortcutAction.TogglePin, ShortcutAction.SentenceMeaning }) Register(a); }
            catch { EnableFeedback(false); throw; }
        }
    }
    private void UnregisterAll() { foreach (int id in registered) NativeMethods.UnregisterHotKey(source.Handle, id); registered.Clear(); }
    private IntPtr HandleMessage(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam, ref bool handled)
    { if (message == 0x0312) { handled = true; Pressed?.Invoke(wParam.ToInt32()); } return IntPtr.Zero; }
    public void Dispose() { UnregisterAll(); source.Dispose(); }
}
