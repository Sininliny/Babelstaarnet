using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace Babelstaarnet.Windows;

internal static class CaptureVisibility
{
    internal static void Run(IntPtr window, Action capture, Action hide, Action restore)
    {
        bool excluded = NativeMethods.SetWindowDisplayAffinity(window, 0x11);
        try
        {
            if (!excluded) hide();
            // Wait for the compositor before copying pixels, so the reader
            // cannot recognize its own previous translation bubble.
            NativeMethods.DwmFlush();
            capture();
        }
        finally
        {
            if (excluded)
            {
                if (!NativeMethods.SetWindowDisplayAffinity(window, 0))
                    throw new Win32Exception(Marshal.GetLastWin32Error(),
                        "Could not restore the translation bubble's screenshot visibility.");
            }
            else restore();
            NativeMethods.DwmFlush();
        }
    }
}
