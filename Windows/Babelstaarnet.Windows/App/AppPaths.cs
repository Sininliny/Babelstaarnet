using System;
using System.IO;

namespace Babelstaarnet.Windows;

internal static class AppPaths
{
    public static string DataDirectory =>
        Environment.GetEnvironmentVariable("BABELSTAARNET_DATA_DIRECTORY") is { Length: > 0 } directory
            ? Path.GetFullPath(directory)
            : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Babelstaarnet");
    public static string Python => Path.Combine(DataDirectory, "argos-venv", "Scripts", "python.exe");
    public static string Bridge => Path.Combine(AppContext.BaseDirectory, "LocalEngines", "argos_bridge.py");
    public static string SpeechBridge => Path.Combine(AppContext.BaseDirectory, "LocalEngines", "piper_bridge.py");
    public static string SpeechInstaller => Path.Combine(AppContext.BaseDirectory, "LocalEngines", "install-neural-voice.ps1");
    public static string Installer => Path.Combine(AppContext.BaseDirectory, "LocalEngines", "install-local-engines.ps1");
}
