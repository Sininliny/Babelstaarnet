using Microsoft.Win32;
using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Babelstaarnet.Windows;

internal sealed class BrandIcons : IDisposable
{
    private readonly Dictionary<string, Icon> icons = [];
    internal static Stream Resource(string name) => Assembly.GetExecutingAssembly().GetManifestResourceStream("Babelstaarnet.Assets." + name) ?? throw new FileNotFoundException("Missing app icon: " + name);
    public static ImageSource AppImage => Image("Babelstaarnet.ico");
    public static ImageSource Image(string name)
    {
        using var stream = Resource(name);
        var decoder = new IconBitmapDecoder(stream, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
        var frame = decoder.Frames.OrderByDescending(f => f.PixelWidth).First(); frame.Freeze(); return frame;
    }
    internal static bool LightTaskbar => (Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "SystemUsesLightTheme", 0) as int?) == 1;
    public Icon Tray(bool active, bool? light = null)
    {
        string name = "tray-" + (active ? "active" : "inactive") + "-" + ((light ?? LightTaskbar) ? "light" : "dark") + ".ico";
        if (!icons.TryGetValue(name, out var icon)) { using var stream = Resource(name); using var decoded = new Icon(stream, new Size(32, 32)); icon = (Icon)decoded.Clone(); icons[name] = icon; }
        return icon;
    }
    public void Dispose() { foreach (var icon in icons.Values) icon.Dispose(); icons.Clear(); }
}
