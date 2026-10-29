using Babelstaarnet.Core;
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace Babelstaarnet.Windows;

internal static class OcrImagePreparation
{
    internal static Bitmap? Separate(Bitmap image)
    {
        if ((long)image.Width * image.Height > 8_000_000) return null;
        byte[] pixels = PixelSnapshot.Capture(image, default).Bytes;
        byte[] gray = new byte[image.Width * image.Height];
        if (SharedPolicy.bp_ocr_separate(pixels, pixels.Length, image.Width, image.Height, 1, gray, gray.Length) == 0) return null;
        for (int i = 0; i < gray.Length; i++) { pixels[i * 4] = pixels[i * 4 + 1] = pixels[i * 4 + 2] = gray[i]; pixels[i * 4 + 3] = 255; }
        var result = new Bitmap(image.Width, image.Height, PixelFormat.Format32bppArgb);
        var locked = result.LockBits(new Rectangle(Point.Empty, result.Size), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        try { for (int row = 0; row < image.Height; row++) Marshal.Copy(pixels, row * image.Width * 4, IntPtr.Add(locked.Scan0, row * locked.Stride), image.Width * 4); }
        finally { result.UnlockBits(locked); }
        return result;
    }
}
