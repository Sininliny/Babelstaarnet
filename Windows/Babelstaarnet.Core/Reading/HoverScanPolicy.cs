namespace Babelstaarnet.Core;

public static class HoverScanPolicy
{
    public static readonly TimeSpan SettleDelay = TimeSpan.FromMilliseconds(35);
    public static readonly TimeSpan RefreshInterval = TimeSpan.FromMilliseconds(600);
    public static readonly TimeSpan MissRetryInterval = TimeSpan.FromMilliseconds(150);

    public static bool Moved(PixelPoint a, PixelPoint b) =>
        Math.Abs((long)a.X - b.X) >= 3 || Math.Abs((long)a.Y - b.Y) >= 3;

    public static bool ShouldScan(PixelPoint pointer, PixelPoint? lastScanPoint,
        DateTimeOffset settledSince, DateTimeOffset lastScan, DateTimeOffset now, bool hasHit = true) =>
        now - settledSince >= SettleDelay &&
        (lastScanPoint is not { } last || Moved(pointer, last) || now - lastScan >= (hasHit ? RefreshInterval : MissRetryInterval));
}
