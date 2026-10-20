using Babelstaarnet.Core;
using Babelstaarnet.Windows;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;

internal static class WindowLifecycleChecks
{
    internal static int Run(string temporary)
    {
        Exception? failure = null;
        int checks = 0;
        var thread = new Thread(() =>
        {
            try
            {
                var model = new ReaderUiModel(new ReaderPreferences(), new VocabularyStore(Path.Combine(temporary, "window-vocabulary.json")), Path.Combine(temporary, "window-preferences.json"));
                var popup = new TrayPopup(model);
                _ = new WindowInteropHelper(popup).EnsureHandle();
                int closing = 0, closed = 0, deactivated = 0;
                popup.Deactivated += (_, _) => deactivated++;
                popup.Closed += (_, _) => closed++;
                popup.Closing += (_, _) =>
                {
                    closing++;
                    // Windows deactivates the popup while destroying it when
                    // Settings or Word Book takes over. Reproduce that event
                    // order on our hidden HWND without activating the desktop.
                    typeof(Window).GetMethod("OnDeactivated", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(popup, [EventArgs.Empty]);
                };
                popup.Close();
                if (closing != 1 || closed != 1 || deactivated != 1) throw new Exception("Closing a tray popup must tolerate deactivation during destruction and close exactly once.");
                checks++;
                popup.Dismiss(); popup.Dismiss();
                if (closed != 1) throw new Exception("Repeated dismissals of an already closed popup must be harmless."); checks++;

                foreach (bool settings in new[] { true, false })
                    for (int iteration = 0; iteration < 3; iteration++)
                    {
                        TrayPopup current = null!; Window? destination = null; int opened = 0, popupClosed = 0;
                        Action navigate = () =>
                        {
                            current.Dismiss();
                            destination = settings ? ReaderApp.CreateSettingsWindow(model) : new WordBookWindow(model.Vocabulary, _ => { }, model.Preferences);
                            destination.Loaded += (_, _) => opened++;
                            ShowInvisible(destination);
                        };
                        if (settings) model.OpenSettings = navigate; else model.OpenBook = navigate;
                        current = new TrayPopup(model); current.Closed += (_, _) => popupClosed++;
                        current.Closing += (_, _) => typeof(Window).GetMethod("OnDeactivated", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(current, [EventArgs.Empty]);
                        ShowInvisible(current);
                        var button = Descendants<Button>(current).Single(b => b.Content is string title && (settings ? title == "Settings…" : title == model.BookTitle));
                        button.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
                        Pump();
                        if (opened != 1 || popupClosed != 1 || destination is null || !destination.IsVisible)
                            throw new Exception("The tray action must close its popup once and fully load " + (settings ? "Settings." : "Word Book."));
                        destination.Close(); current.Dismiss(); Pump(); checks++;
                    }

                var canceled = new TrayPopup(model); _ = new WindowInteropHelper(canceled).EnsureHandle(); bool veto = true; int cancelClosed = 0;
                canceled.Closing += (_, e) => e.Cancel = veto; canceled.Closed += (_, _) => cancelClosed++;
                canceled.Dismiss(); veto = false; canceled.Dismiss();
                if (cancelClosed != 1) throw new Exception("A canceled close must not leave the popup permanently unable to dismiss."); checks++;
            }
            catch (Exception error) { failure = error; }
        });
        thread.SetApartmentState(ApartmentState.STA); thread.Start(); thread.Join();
        if (failure is not null) throw new Exception("Tray/settings window lifecycle regression.", failure);
        return checks;
    }
    private static void ShowInvisible(Window window)
    {
        // Exercise actual Show/Loaded/Close with our own windows, without
        // changing focus, drawing over the desktop or intercepting input.
        window.ShowActivated = false; window.ShowInTaskbar = false; window.Opacity = 0;
        window.WindowStartupLocation = WindowStartupLocation.Manual; window.Left = -20000; window.Top = -20000;
        var handle = new WindowInteropHelper(window).EnsureHandle();
        NativeMethods.SetWindowLongPtr(handle, -20, new IntPtr(NativeMethods.GetWindowLongPtr(handle, -20).ToInt64() | 0x080000A0));
        window.Show(); Pump();
    }
    private static void Pump() => Dispatcher.CurrentDispatcher.Invoke(DispatcherPriority.ContextIdle, new Action(() => { }));
    private static IEnumerable<T> Descendants<T>(DependencyObject root) where T : DependencyObject
    {
        if (root is T item) yield return item;
        for (int i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++)
            foreach (var child in Descendants<T>(VisualTreeHelper.GetChild(root, i))) yield return child;
    }
}
