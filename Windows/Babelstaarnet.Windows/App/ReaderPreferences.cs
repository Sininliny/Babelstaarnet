using Babelstaarnet.Core;
using System;
using System.IO;
using System.Text.Json;

namespace Babelstaarnet.Windows;

internal sealed class ReaderPreferences
{
    public string Appearance { get; set; } = "system";
    public bool SupportedReading { get; set; }
    public string SpeechEngine { get; set; } = "piper";
    public bool ReadAloud { get; set; } = true;
    public double SpeakAfterSeconds { get; set; } = .45;
    public bool WordMeaning { get; set; } = true;
    public bool WholeSentence { get; set; } = true;
    public bool FollowScreenChanges { get; set; } = true;
    public bool PowerSaving { get; set; } = true;
    public bool ContextualMeanings { get; set; } = true;
    public HotKeyConfiguration Shortcuts { get; set; } = HotKeyConfiguration.Defaults;
    public static ReaderPreferences Load(string? path = null)
    {
        string file = path ?? Path.Combine(AppPaths.DataDirectory, "preferences.json");
        if (!File.Exists(file)) return new();
        var preferences = JsonSerializer.Deserialize<ReaderPreferences>(File.ReadAllText(file)) ?? throw new InvalidDataException("The preferences file is empty.");
        preferences.Normalize(); return preferences;
    }
    public void Normalize()
    {
        if (!double.IsFinite(SpeakAfterSeconds)) SpeakAfterSeconds = .45;
        SpeakAfterSeconds = Math.Clamp(Math.Round(SpeakAfterSeconds / .05) * .05, .2, 1.2);
        if (Appearance is not ("system" or "light" or "dark")) Appearance = "system";
        if (SpeechEngine is not ("piper" or "windows")) SpeechEngine = "piper";
        if (Shortcuts is null || Shortcuts.ValidationError() is not null) Shortcuts = HotKeyConfiguration.Defaults;
    }
    public void Save(string? path = null)
    {
        Normalize(); string file = path ?? Path.Combine(AppPaths.DataDirectory, "preferences.json");
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(file))!);
        string temporary = file + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(this)); File.Move(temporary, file, overwrite: true);
    }
}
