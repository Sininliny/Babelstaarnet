using Babelstaarnet.Core;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using Forms = System.Windows.Forms;

namespace Babelstaarnet.Windows;

// Two independent nonactivating panels, as on macOS. A single large window
// containing both would intercept the article between them.
internal sealed class OverlayWindow : IDisposable
{
    private readonly OverlayCard card = new();
    private readonly SentenceCard sentence = new();
    private readonly BubbleWindow wordWindow;
    private readonly BubbleWindow sentenceWindow;
    private readonly BubbleWindow markerWindow;
    private HoveredText? last;
    private readonly FeedbackMemory feedbackMemory = new();
    private bool? feedback;
    public bool IsVisible => wordWindow.IsVisible || sentenceWindow.IsVisible;
    public event Action? Known;
    public event Action? Unknown;
    public event Action? Pin;
    public event Action? Listen;
    public OverlayWindow()
    {
        wordWindow = new BubbleWindow(new FloatingSurface(card), "Babelstårnet · word");
        sentenceWindow = new BubbleWindow(new FloatingSurface(sentence), "Babelstårnet · sentence");
        markerWindow = new BubbleWindow(new Border { Background = Ui.Accent, CornerRadius = new CornerRadius(1) }, "Babelstårnet · focus", marker: true);
        card.Known += () => Known?.Invoke(); card.Unknown += () => Unknown?.Invoke();
        card.Pin += () => Pin?.Invoke(); card.Listen += () => Listen?.Invoke();
    }
    private CaptureLease ExcludeForCapture(PixelRect area) => new(new[] { wordWindow, sentenceWindow, markerWindow }
        .Where(w => w.IsVisible && OverlayLayout.Intersects(area, w.WindowFrame)).ToArray());
    public void CaptureWithoutOverlay(PixelRect area, Action capture)
    {
        using var lease = ExcludeForCapture(area);
        if (lease.Changed) NativeMethods.DwmFlush();
        capture();
    }
    public async Task CaptureWithoutOverlayAsync(PixelRect area, Action capture, CancellationToken cancellationToken)
    {
        // Exclusion/restoration stay on the dispatcher. Waiting for the
        // compositor and copying pixels run on a worker, without freezing UI.
        using var lease = ExcludeForCapture(area);
        await Task.Run(() => { if (lease.Changed) NativeMethods.DwmFlush(); cancellationToken.ThrowIfCancellationRequested(); capture(); }, cancellationToken);
    }
    private sealed class CaptureLease : IDisposable
    {
        private readonly List<IDisposable> exclusions = [];
        internal bool Changed => exclusions.Count > 0;
        internal CaptureLease(BubbleWindow[] windows)
        {
            try
            {
                foreach (var window in windows) exclusions.Add(CaptureVisibility.Exclude(window.Handle, window.Hide, window.Show, () => !window.ClosedPermanently));
            }
            catch { Dispose(); throw; }
        }
        public void Dispose()
        {
            Exception? failure = null;
            foreach (var exclusion in exclusions) try { exclusion.Dispose(); } catch (Exception error) { failure ??= error; }
            exclusions.Clear(); if (failure is not null) throw failure;
        }
    }

    public void Present(HoveredText text, string translation, string readingBridge, bool pinned, bool loading, bool known,
        IReadOnlyList<BridgeToken>? tokens = null, bool showWord = true, bool showSentence = true, HotKeyConfiguration? shortcuts = null,
        int knowledgeLevel = 0, IReadOnlyList<BridgeToken>? explanationTokens = null)
    {
        if (!showWord && !showSentence) { Hide(); return; }
        card.SetShortcuts(shortcuts ?? HotKeyConfiguration.Defaults);
        if (last?.Word != text.Word || last.Line.Text != text.Line.Text) { feedback = feedbackMemory.Recall(text.Word.Text, DateTimeOffset.Now); card.SetFeedback(feedback); }
        last = text;
        card.SetContent(text, translation, readingBridge, pinned, loading, known, knowledgeLevel, explanationTokens);
        sentence.SetContent(tokens ?? BridgePresentation.Tokens(text, ReadingPolicy.Glosses, _ => false));
        sentence.SetMode(!showWord, DanishLanguage.ConciseMeaning(translation, text.Word.Text), knowledgeLevel); sentence.SetFeedback(feedback);
        var display = Forms.Screen.FromPoint(new System.Drawing.Point(text.Word.Bounds.X, text.Word.Bounds.Y));
        var work = display.WorkingArea;
        var screen = new PixelRect(work.X, work.Y, work.Width, work.Height);
        double scale = wordWindow.PrepareMonitor(display.DeviceName, text.Word.Bounds);
        sentenceWindow.PrepareMonitor(display.DeviceName, text.Word.Bounds);
        markerWindow.PrepareMonitor(display.DeviceName, text.Word.Bounds);
        var wordSize = wordWindow.MeasureContent(scale);
        var sentenceSize = sentenceWindow.MeasureContent(scale);
        var source = OverlayLayout.SourceFrame(text);
        var pair = showWord && showSentence ? OverlayLayout.Place(text.Word.Bounds, source, wordSize, sentenceSize, screen, scale) : null;
        if (pair is not null)
        {
            wordWindow.Place(pair.Word, scale); sentenceWindow.Place(pair.Sentence, scale);
        }
        else
        {
            wordWindow.Hide(); sentenceWindow.Hide();
            bool sentenceOnly = !showWord && showSentence;
            if (OverlayLayout.PlaceSingle(text.Word.Bounds, source, sentenceOnly ? sentenceSize : wordSize, screen, sentenceOnly, scale) is { } frame)
            { if (sentenceOnly) sentenceWindow.Place(frame, scale); else wordWindow.Place(frame, scale); }
            else { Hide(); return; }
        }
        var rule = OverlayLayout.FocusRule(text.Word.Bounds);
        markerWindow.Place(rule with { Height = Math.Max(2, (int)Math.Round(2 * scale)), Y = text.Word.Bounds.Bottom + (int)Math.Round(2 * scale) }, scale);
    }
    internal bool CheckNativeSurfaces()
    {
        foreach (var window in new[] { wordWindow, sentenceWindow, markerWindow })
        {
            long style = NativeMethods.GetWindowLongPtr(window.Handle, -20).ToInt64();
            if ((style & 0x08000080L) != 0x08000080L || NativeMethods.GetDpiForWindow(window.Handle) == 0 || window.IsVisible) return false;
        }
        return (NativeMethods.GetWindowLongPtr(markerWindow.Handle, -20).ToInt64() & 0x20) != 0;
    }
    public void SetFeedback(bool known)
    {
        feedback = known;
        if (last is not null) feedbackMemory.Remember(last.Word.Text, known, DateTimeOffset.Now);
        card.SetFeedback(known, animate: known); sentence.SetFeedback(known);
    }
    public bool Contains(PixelPoint point) => wordWindow.IsVisible && wordWindow.ContentFrame.Contains(point) || sentenceWindow.IsVisible && sentenceWindow.ContentFrame.Contains(point);
    public void Hide() { wordWindow.Hide(); sentenceWindow.Hide(); markerWindow.Hide(); last = null; }
    public void Dispose() { wordWindow.Close(); sentenceWindow.Close(); markerWindow.Close(); }

    private sealed class BubbleWindow : Window
    {
        private readonly FrameworkElement panel;
        private readonly int shadow;
        private string? monitor;
        internal bool ClosedPermanently { get; private set; }
        internal PixelRect ContentFrame { get; private set; }
        internal PixelRect WindowFrame { get; private set; }
        internal IntPtr Handle => new WindowInteropHelper(this).EnsureHandle();
        internal BubbleWindow(FrameworkElement panel, string title, bool marker = false)
        {
            this.panel = panel; shadow = marker ? 0 : 18;
            Closed += (_, _) => ClosedPermanently = true;
            Title = title; WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize;
            ShowInTaskbar = false; ShowActivated = false; Topmost = true; AllowsTransparency = true;
            Background = Brushes.Transparent;
            Content = new Border { Padding = new Thickness(shadow), Child = panel };
            SourceInitialized += (_, _) =>
            {
                long extended = NativeMethods.GetWindowLongPtr(Handle, -20).ToInt64();
                NativeMethods.SetWindowLongPtr(Handle, -20, new IntPtr(extended | 0x08000080L | (marker ? 0x20L : 0)));
                HwndSource.FromHwnd(Handle)?.AddHook((IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam, ref bool handled) =>
                {
                    if (message == 0x0021) { handled = true; return new IntPtr(3); }
                    if (marker && message == 0x0084) { handled = true; return new IntPtr(-1); }
                    return IntPtr.Zero;
                });
            };
        }
        internal double PrepareMonitor(string display, PixelRect anchor)
        {
            if (monitor != display)
            {
                Hide(); NativeMethods.SetWindowPos(Handle, new IntPtr(-1), anchor.X, anchor.Y, 0, 0, 0x11);
                monitor = display;
            }
            return NativeMethods.GetDpiForWindow(Handle) / 96.0;
        }
        internal PixelSize MeasureContent(double scale)
        {
            panel.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
            return new((int)Math.Ceiling(panel.DesiredSize.Width * scale), (int)Math.Ceiling(panel.DesiredSize.Height * scale));
        }
        internal void Place(PixelRect frame, double scale)
        {
            if (ContentFrame == frame && IsVisible) return;
            ContentFrame = frame;
            int margin = (int)Math.Round(shadow * scale);
            Width = frame.Width / scale + shadow * 2; Height = frame.Height / scale + shadow * 2;
            NativeMethods.SetWindowPos(Handle, new IntPtr(-1), frame.X - margin, frame.Y - margin, frame.Width + margin * 2, frame.Height + margin * 2, 0x10);
            WindowFrame = new(frame.X - margin, frame.Y - margin, frame.Width + margin * 2, frame.Height + margin * 2);
            if (!IsVisible) Show();
        }
    }
}
