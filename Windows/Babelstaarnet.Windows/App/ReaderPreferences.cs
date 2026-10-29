using Babelstaarnet.Core;
using System;
using System.IO;
using System.Linq;
using System.Text.Json;

namespace Babelstaarnet.Windows;

internal sealed class ReaderPreferences
{
    public string SourceLanguage { get; set; } = "da";
    public string TargetLanguage { get; set; } = "en";
    [System.Text.Json.Serialization.JsonIgnore]
    public ReadingLanguagePair LanguagePair => LanguageCatalog.Pair(SourceLanguage, TargetLanguage);
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
        string raw = File.ReadAllText(file);
        var preferences = JsonSerializer.Deserialize<ReaderPreferences>(raw) ?? throw new InvalidDataException("The preferences file is empty.");
        using var document = JsonDocument.Parse(raw);
        if (preferences.Shortcuts is { } shortcuts && document.RootElement.TryGetProperty("Shortcuts", out var prior) && prior.ValueKind == JsonValueKind.Object && !prior.TryGetProperty("SentenceMeaning", out _))
        {
            AppShortcut[] occupied = [shortcuts.ToggleLearning, shortcuts.Known, shortcuts.DontKnow, shortcuts.TogglePin];
            preferences.Shortcuts = shortcuts with { SentenceMeaning = Enumerable.Range(0, 16).Select(m => new AppShortcut(52, (uint)m)).First(s => !occupied.Contains(s)) };
        }
        preferences.Normalize(); return preferences;
    }
    public void Normalize()
    {
        if (!LanguageCatalog.Contains(SourceLanguage)) SourceLanguage = "da";
        if (!LanguageCatalog.Contains(TargetLanguage) || TargetLanguage == SourceLanguage) TargetLanguage = SourceLanguage == "en" ? "da" : "en";
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
