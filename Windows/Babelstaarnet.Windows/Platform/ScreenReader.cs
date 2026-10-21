using Babelstaarnet.Core;
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Linq;
using System.Runtime.InteropServices.WindowsRuntime;
using System.Threading;
using System.Threading.Tasks;
using Windows.Globalization;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using Forms = System.Windows.Forms;

namespace Babelstaarnet.Windows;

internal sealed class ScreenReader
{
    private readonly SemaphoreSlim recognitionGate = new(1);
    private OcrEngine? engine;
    private PixelRect? captureArea;
    private PixelRect? captureScreen;
    private PixelSnapshot? snapshot;
    private PixelPoint cachedOrigin => snapshot?.Origin ?? default;
    private Size cachedSize => snapshot?.Size ?? default;
    private IReadOnlyList<RecognizedLine> cachedLines = Array.Empty<RecognizedLine>();
    private DateTimeOffset fullCaptureAt;
    private double? textHeight;
    private bool previousWholeDisplay;
    internal int Recognitions { get; private set; }
    internal int SnapshotHits { get; private set; }
    public static bool DanishAvailable => OcrEngine.IsLanguageSupported(new Language("da-DK"));

    public async Task WarmAsync()
    {
        using var blank = new Bitmap(700, 100, PixelFormat.Format32bppArgb);
        using (var graphics = Graphics.FromImage(blank))
        using (var font = new Font("Segoe UI", 24))
        {
            graphics.Clear(Color.White);
            graphics.DrawString("Jeg spiser æbler.", font, Brushes.Black, 12, 24);
        }
        await RecognizeAsync(blank, new(0, 0), CancellationToken.None).ConfigureAwait(false);
    }

    public async Task<IReadOnlyList<RecognizedLine>> ReadAsync(PixelPoint pointer,
        CancellationToken cancellationToken, Func<PixelRect, Action, CancellationToken, Task> captureWithoutOverlay, bool captureWholeDisplay = false)
    {
        // Reuse the page's word boxes only after checking the line's current
        // pixels. Moving to the next word avoids both OCR and compositor work;
        // scrolling, selection and page updates still invalidate the snapshot.
        if (!captureWholeDisplay && DateTimeOffset.UtcNow - fullCaptureAt < HoverScanPolicy.RefreshInterval && ReadingPolicy.HitTest(cachedLines, pointer) is { } hit && snapshot is not null)
        {
            int left = hit.Line.Words.Min(w => w.Bounds.X);
            int top = hit.Line.Words.Min(w => w.Bounds.Y);
            int right = hit.Line.Words.Max(w => w.Bounds.Right);
            int bottom = hit.Line.Words.Max(w => w.Bounds.Bottom);
            var patch = new PixelRect(Math.Max(left - 2, cachedOrigin.X), Math.Max(top - 2, cachedOrigin.Y), 0, 0);
            patch = patch with { Width = Math.Min(right + 2, cachedOrigin.X + cachedSize.Width) - patch.X,
                Height = Math.Min(bottom + 2, cachedOrigin.Y + cachedSize.Height) - patch.Y };
            if (patch.Width > 0 && patch.Height > 0)
            {
                using var line = await CaptureAsync(patch, captureWithoutOverlay, cancellationToken);
                if (MatchesSnapshot(line, new(patch.X, patch.Y)))
                { SnapshotHits++; return cachedLines; }
            }
        }
        var screen = Forms.Screen.FromPoint(new Point(pointer.X, pointer.Y)).Bounds;
        var screenRect = new PixelRect(screen.X, screen.Y, screen.Width, screen.Height);
        // Keep the crop still while reading nearby words. Its fresh pixels are
        // checked every time, so scrolling invalidates the recognized snapshot.
        var area = previousWholeDisplay == captureWholeDisplay && captureScreen == screenRect && captureArea is { } previous &&
            pointer.X >= previous.X + 80 && pointer.X < previous.Right - 80 &&
            pointer.Y >= previous.Y + 40 && pointer.Y < previous.Bottom - 40
            ? previous : AdaptiveCapture.Plan(pointer, screenRect, textHeight, NativeMethods.MonitorScale(pointer.X, pointer.Y));
        if (captureWholeDisplay) area = screenRect;
        captureScreen = screenRect;
        captureArea = area;
        previousWholeDisplay = captureWholeDisplay;
        // All capture and hit-test coordinates remain physical pixels, including
        // monitors with negative origins and different scaling factors.
        IReadOnlyList<RecognizedLine> lines;
        using (var bitmap = await CaptureAsync(area, captureWithoutOverlay, cancellationToken))
            lines = await Task.Run(() => RecognizeAsync(bitmap, new(area.X, area.Y), cancellationToken), cancellationToken);
        cancellationToken.ThrowIfCancellationRequested(); fullCaptureAt = DateTimeOffset.UtcNow;
        if (!captureWholeDisplay && ReadingPolicy.HitTest(lines, pointer) is null && AdaptiveCapture.NeedsExpansion(lines, area))
        {
            area = AdaptiveCapture.Plan(pointer, screenRect, textHeight, NativeMethods.MonitorScale(pointer.X, pointer.Y), expansion: 1.6);
            using var expanded = await CaptureAsync(area, captureWithoutOverlay, cancellationToken);
            lines = await Task.Run(() => RecognizeAsync(expanded, new(area.X, area.Y), cancellationToken), cancellationToken);
            captureArea = area;
        }
        var heights = lines.SelectMany(l => l.Words).Select(w => w.Bounds.Height).Where(h => h is >= 4 and <= 180).Order().ToArray();
        if (heights.Length > 0) textHeight = textHeight is { } priorHeight ? priorHeight * .65 + heights[heights.Length / 2] * .35 : heights[heights.Length / 2];
        return lines;
    }

    private static async Task<Bitmap> CaptureAsync(PixelRect area, Func<PixelRect, Action, CancellationToken, Task> captureWithoutOverlay, CancellationToken cancellationToken)
    {
        Bitmap? bitmap = null;
        try
        {
            await captureWithoutOverlay(area, () =>
            {
                bitmap = new Bitmap(area.Width, area.Height, PixelFormat.Format32bppArgb);
                using var graphics = Graphics.FromImage(bitmap);
                graphics.CopyFromScreen(area.X, area.Y, 0, 0, bitmap.Size, CopyPixelOperation.SourceCopy);
            }, cancellationToken);
            cancellationToken.ThrowIfCancellationRequested(); return bitmap!;
        }
        catch { bitmap?.Dispose(); throw; }
    }

    internal bool MatchesSnapshot(Bitmap bitmap, PixelPoint origin) => snapshot?.Matches(bitmap, origin) == true;

    internal async Task<IReadOnlyList<RecognizedLine>> RecognizeAsync(Bitmap bitmap,
        PixelPoint origin, CancellationToken cancellationToken)
    {
        await recognitionGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try { return await RecognizeOwnedAsync(bitmap, origin, cancellationToken).ConfigureAwait(false); }
        finally { recognitionGate.Release(); }
    }

    private async Task<IReadOnlyList<RecognizedLine>> RecognizeOwnedAsync(Bitmap bitmap,
        PixelPoint origin, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        engine ??= OcrEngine.TryCreateFromLanguage(new Language("da-DK")) ??
            throw new InvalidOperationException("Install Danish optical character recognition in Windows Settings → Time & language → Language & region → Danish → Language options.");
        if (origin == cachedOrigin && bitmap.Size == cachedSize && MatchesSnapshot(bitmap, origin)) return cachedLines;
        var nextSnapshot = PixelSnapshot.Capture(bitmap, origin); byte[] raw = nextSnapshot.Bytes;
        // Static snapshots can cover a whole 4K/8K monitor. Respect the OCR
        // runtime's image limit while returning physical source coordinates.
        double ratio = Math.Min(1, (double)OcrEngine.MaxImageDimension / Math.Max(bitmap.Width, bitmap.Height));
        using var resized = ratio < 1 ? new Bitmap(Math.Max(1, (int)Math.Floor(bitmap.Width * ratio)), Math.Max(1, (int)Math.Floor(bitmap.Height * ratio)), PixelFormat.Format32bppArgb) : null;
        if (resized is not null)
        {
            using var graphics = Graphics.FromImage(resized); graphics.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
            graphics.DrawImage(bitmap, new Rectangle(Point.Empty, resized.Size));
        }
        var input = resized ?? bitmap; double scaleX = (double)bitmap.Width / input.Width, scaleY = (double)bitmap.Height / input.Height;
        using var pixels = SoftwareBitmap.CreateCopyFromBuffer((resized is null ? raw : PixelSnapshot.Capture(input, default).Bytes).AsBuffer(), BitmapPixelFormat.Bgra8,
            input.Width, input.Height, BitmapAlphaMode.Ignore);
        var result = await engine.RecognizeAsync(pixels).AsTask(cancellationToken).ConfigureAwait(false);
        Recognitions++;
        cancellationToken.ThrowIfCancellationRequested();
        var lines = result.Lines.Select(line => new RecognizedLine(line.Text,
            line.Words.Select(word => new RecognizedWord(word.Text, new PixelRect(
                origin.X + (int)Math.Floor(word.BoundingRect.X * scaleX), origin.Y + (int)Math.Floor(word.BoundingRect.Y * scaleY),
                (int)Math.Ceiling(word.BoundingRect.Width * scaleX), (int)Math.Ceiling(word.BoundingRect.Height * scaleY))))
            .ToArray())).ToArray();
        snapshot = nextSnapshot;
        cachedLines = lines;
        return lines;
    }

}
