using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace Babelstaarnet.Windows;

internal static class CaptureVisibility
{
    internal static IDisposable Exclude(IntPtr window, Action hide, Action restore, Func<bool>? isAlive = null) => new Exclusion(window, hide, restore, isAlive);
    internal static void Run(IntPtr window, Action capture, Action hide, Action restore)
    {
        using var exclusion = Exclude(window, hide, restore);
        NativeMethods.DwmFlush(); capture();
    }
    private sealed class Exclusion : IDisposable
    {
        private readonly IntPtr window;
        private readonly Action hide, restore;
        private readonly Func<bool>? isAlive;
        private readonly bool excluded;
        private bool disposed;
        internal Exclusion(IntPtr window, Action hide, Action restore, Func<bool>? isAlive)
        {
            this.window = window; this.hide = hide; this.restore = restore; this.isAlive = isAlive;
            excluded = NativeMethods.SetWindowDisplayAffinity(window, 0x11);
            if (!excluded) hide();
        }
        public void Dispose()
        {
            if (disposed) return; disposed = true;
            if (isAlive?.Invoke() == false) return;
            if (!excluded) restore();
            else if (!NativeMethods.SetWindowDisplayAffinity(window, 0))
            {
                int error = Marshal.GetLastWin32Error(); hide();
                throw new Win32Exception(error, "Could not restore the translation bubble's screenshot visibility.");
            }
        }
    }
}
