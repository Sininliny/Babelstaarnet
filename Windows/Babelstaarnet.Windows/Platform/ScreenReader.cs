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
    private readonly ReadingLanguage language;
    private readonly double preferredScale;
    internal ScreenReader(double preferredScale = 2, ReadingLanguage? language = null) { this.language = language ?? LanguageCatalog.Get("da"); this.preferredScale = double.IsFinite(preferredScale) ? Math.Clamp(preferredScale, 1, 2) : 2; }
    private readonly SemaphoreSlim recognitionGate = new(1);
    private OcrEngine? engine;
    private PixelRect? captureArea;
    private PixelRect? captureScreen;
    private PixelSnapshot? snapshot;
    private readonly Queue<PixelRect> recoveryWindows = new();
    private PixelPoint cachedOrigin => snapshot?.Origin ?? default;
    private Size cachedSize => snapshot?.Size ?? default;
    private IReadOnlyList<RecognizedLine> cachedLines = Array.Empty<RecognizedLine>();
    private DateTimeOffset fullCaptureAt;
    private double? textHeight;
    private bool previousWholeDisplay;
    internal int Recognitions { get; private set; }
    internal int SnapshotHits { get; private set; }
    public bool IsAvailable => OcrEngine.IsLanguageSupported(new Language(language.OcrWindows));
    public static bool DanishAvailable => OcrEngine.IsLanguageSupported(new Language("da-DK"));

    public async Task WarmAsync()
    {
        using var blank = new Bitmap(700, 100, PixelFormat.Format32bppArgb);
        using (var graphics = Graphics.FromImage(blank))
        using (var font = new Font("Segoe UI", 24))
        {
            graphics.Clear(Color.White);
            graphics.DrawString(language.Sample, font, Brushes.Black, 12, 24);
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
            lines = await Task.Run(() => RecognizeAsync(bitmap, new(area.X, area.Y), cancellationToken, pointer), cancellationToken);
        cancellationToken.ThrowIfCancellationRequested(); fullCaptureAt = DateTimeOffset.UtcNow;
        if (!captureWholeDisplay && AdaptiveCapture.NeedsExpansion(lines, area, pointer))
        {
            area = AdaptiveCapture.Plan(pointer, screenRect, textHeight, NativeMethods.MonitorScale(pointer.X, pointer.Y), expansion: 1.6);
            using var expanded = await CaptureAsync(area, captureWithoutOverlay, cancellationToken);
            lines = await Task.Run(() => RecognizeAsync(expanded, new(area.X, area.Y), cancellationToken, pointer), cancellationToken);
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
        PixelPoint origin, CancellationToken cancellationToken, PixelPoint? focus = null)
    {
        await recognitionGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try { return await RecognizeOwnedAsync(bitmap, origin, cancellationToken, focus).ConfigureAwait(false); }
        catch { snapshot = null; cachedLines = Array.Empty<RecognizedLine>(); recoveryWindows.Clear(); throw; }
        finally { recognitionGate.Release(); }
    }

    private async Task<IReadOnlyList<RecognizedLine>> RecognizeOwnedAsync(Bitmap bitmap,
        PixelPoint origin, CancellationToken cancellationToken, PixelPoint? focus)
    {
        cancellationToken.ThrowIfCancellationRequested();
        engine ??= OcrEngine.TryCreateFromLanguage(new Language(language.OcrWindows)) ??
            throw new InvalidOperationException($"Install {language.Name} OCR in Settings → Languages & packs or Windows language options.");
        bool same = origin == cachedOrigin && bitmap.Size == cachedSize && MatchesSnapshot(bitmap, origin);
        IReadOnlyList<RecognizedLine> lines;
        if (same) lines = cachedLines;
        else
        {
            snapshot = PixelSnapshot.Capture(bitmap, origin); recoveryWindows.Clear();
            double ratio = Math.Min(preferredScale, SharedPolicy.bp_ocr_scale(0, language.Cjk ? 1 : 0, bitmap.Width, bitmap.Height, (int)OcrEngine.MaxImageDimension));
            lines = await RecognizePassAsync(bitmap, origin, ratio, cancellationToken).ConfigureAwait(false);
        }
        var hit = focus is { } point ? ReadingPolicy.HitTest(lines, point) : null;
        bool small = hit is not null && hit.Word.Bounds.Height < (language.Cjk ? 18 : 13);
        bool missing = focus is not null ? hit is null : lines.Count == 0;
        if ((!missing && !small) || focus is { } tried && recoveryWindows.Any(w => w.Contains(tried))) return cachedLines = lines;
        // A bounded, pointer-centred strip preserves source pixels on large
        // monitors. Never enhance or re-recognize a whole 4K capture on retry.
        var local = focus is { } at ? new PixelPoint(at.X - origin.X, at.Y - origin.Y) : new(bitmap.Width / 2, bitmap.Height / 2);
        Rectangle window;
        if (hit is not null)
        {
            var frame = hit.Line.Frame; int padding = Math.Max(8, frame.Height / 2);
            window = Rectangle.Intersect(new Rectangle(0, 0, bitmap.Width, bitmap.Height), new Rectangle(frame.X - origin.X - padding, frame.Y - origin.Y - padding, frame.Width + padding * 2, frame.Height + padding * 2));
        }
        else
        {
            int width = Math.Min(bitmap.Width, 1000), height = Math.Min(bitmap.Height, 140);
            window = new(Math.Clamp(local.X - width / 2, 0, bitmap.Width - width), Math.Clamp(local.Y - height / 2, 0, bitmap.Height - height), width, height);
        }
        if (window.Width <= 0 || window.Height <= 0) return cachedLines = lines;
        var retryOrigin = new PixelPoint(origin.X + window.X, origin.Y + window.Y);
        var retryFrame = new PixelRect(retryOrigin.X, retryOrigin.Y, window.Width, window.Height);
        recoveryWindows.Enqueue(retryFrame); while (recoveryWindows.Count > 4) recoveryWindows.Dequeue();
        using var crop = bitmap.Clone(window, PixelFormat.Format32bppArgb);
        double scale = SharedPolicy.bp_ocr_scale(hit?.Word.Bounds.Height ?? 9, language.Cjk ? 1 : 0, crop.Width, crop.Height, (int)OcrEngine.MaxImageDimension);
        // Keep a high quality raw result authoritative. Colour preparation is
        // a rescue pass; its output is never fed back into another transform.
        using var prepared = OcrImagePreparation.Separate(crop);
        if (prepared is not null)
        {
            var retry = await RecognizePassAsync(prepared, retryOrigin, scale, cancellationToken).ConfigureAwait(false);
            lines = MergeRecovery(lines, retry, focus, retryFrame);
        }
        if (small && scale > preferredScale + .25)
        {
            var retry = await RecognizePassAsync(crop, retryOrigin, scale, cancellationToken).ConfigureAwait(false);
            lines = MergeRecovery(lines, retry, focus, retryFrame);
        }
        return cachedLines = lines;
    }
    private static IReadOnlyList<RecognizedLine> MergeRecovery(IReadOnlyList<RecognizedLine> original, IReadOnlyList<RecognizedLine> retry, PixelPoint? focus, PixelRect frame)
    {
        var before = focus is { } a ? ReadingPolicy.HitTest(original, a) : null;
        var after = focus is { } b ? ReadingPolicy.HitTest(retry, b) : null;
        if (focus is not null && after is null || retry.Count == 0) return original;
        if (before is not null && SentenceBoundary.EndsSentence(before.Line.Text)) return original;
        // More source letters can rescue truncated small text; a retry cannot
        // replace an already readable line with a shorter or equal guess.
        if (before is not null && (after is null || after.Line.Text.Count(char.IsLetter) <= before.Line.Text.Count(char.IsLetter))) return original;
        var selected = after is null ? retry : new[] { after.Line };
        return original.Where(line => !selected.Any(next => Overlaps(line.Frame, next.Frame))).Concat(selected).OrderBy(line => line.Frame.Y).ThenBy(line => line.Frame.X).ToArray();
    }
    private static bool Overlaps(PixelRect a, PixelRect b) => a.X < b.Right && a.Right > b.X && a.Y < b.Bottom && a.Bottom > b.Y;
    private async Task<IReadOnlyList<RecognizedLine>> RecognizePassAsync(Bitmap bitmap, PixelPoint origin, double ratio, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        using var resized = Math.Abs(ratio - 1) > .01 ? new Bitmap(Math.Max(1, (int)Math.Floor(bitmap.Width * ratio)), Math.Max(1, (int)Math.Floor(bitmap.Height * ratio)), PixelFormat.Format32bppArgb) : null;
        if (resized is not null)
        {
            using var graphics = Graphics.FromImage(resized); graphics.Clear(Color.White);
            graphics.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
            if (language.Cjk) graphics.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.HighQuality;
            graphics.DrawImage(bitmap, new Rectangle(Point.Empty, resized.Size));
        }
        var input = resized ?? bitmap; double scaleX = (double)bitmap.Width / input.Width, scaleY = (double)bitmap.Height / input.Height;
        using var pixels = SoftwareBitmap.CreateCopyFromBuffer(PixelSnapshot.Capture(input, default).Bytes.AsBuffer(), BitmapPixelFormat.Bgra8, input.Width, input.Height, BitmapAlphaMode.Ignore);
        var result = await engine!.RecognizeAsync(pixels).AsTask(cancellationToken).ConfigureAwait(false); Recognitions++;
        cancellationToken.ThrowIfCancellationRequested();
        var lines = result.Lines.Select(line => new RecognizedLine(line.Text,
            line.Words.Select(word => new RecognizedWord(word.Text, new PixelRect(
                origin.X + (int)Math.Floor(word.BoundingRect.X * scaleX), origin.Y + (int)Math.Floor(word.BoundingRect.Y * scaleY),
                (int)Math.Ceiling(word.BoundingRect.Width * scaleX), (int)Math.Ceiling(word.BoundingRect.Height * scaleY)))).ToArray())).ToArray();
        return language.Cjk ? lines.Select(CjkWords.SegmentLine).ToArray() : lines;
    }
}
