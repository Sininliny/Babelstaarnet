using Babelstaarnet.Core;
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace Babelstaarnet.Windows;

// Owns the exact pixels used for OCR. Native memory never outlives LockBits;
// matching visits each row in place and allocates only BitmapData metadata.
internal sealed class PixelSnapshot(byte[] bytes, Size size, PixelPoint origin)
{
    internal byte[] Bytes { get; } = bytes;
    internal Size Size { get; } = size;
    internal PixelPoint Origin { get; } = origin;
    internal unsafe bool Matches(Bitmap bitmap, PixelPoint point)
    {
        int x = point.X - Origin.X, y = point.Y - Origin.Y;
        if (x < 0 || y < 0 || x + bitmap.Width > Size.Width || y + bitmap.Height > Size.Height) return false;
        int rowBytes = checked(bitmap.Width * 4);
        var locked = bitmap.LockBits(new Rectangle(Point.Empty, bitmap.Size), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        try
        {
            for (int row = 0; row < bitmap.Height; row++)
            {
                var pixels = new ReadOnlySpan<byte>((byte*)locked.Scan0 + row * locked.Stride, rowBytes);
                if (!pixels.SequenceEqual(Bytes.AsSpan(((y + row) * Size.Width + x) * 4, rowBytes))) return false;
            }
            return true;
        }
        finally { bitmap.UnlockBits(locked); }
    }
    internal static PixelSnapshot Capture(Bitmap bitmap, PixelPoint origin)
    {
        byte[] bytes = GC.AllocateUninitializedArray<byte>(checked(bitmap.Width * bitmap.Height * 4));
        var locked = bitmap.LockBits(new Rectangle(Point.Empty, bitmap.Size), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        try
        {
            int rowBytes = bitmap.Width * 4;
            if (locked.Stride == rowBytes) Marshal.Copy(locked.Scan0, bytes, 0, bytes.Length);
            else for (int row = 0; row < bitmap.Height; row++) Marshal.Copy(IntPtr.Add(locked.Scan0, row * locked.Stride), bytes, row * rowBytes, rowBytes);
        }
        finally { bitmap.UnlockBits(locked); }
        return new(bytes, bitmap.Size, origin);
    }
}
