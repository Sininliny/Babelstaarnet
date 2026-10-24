using Babelstaarnet.Core;
using System;

namespace Babelstaarnet.Windows;

internal sealed class ReaderUiModel
{
    public ReaderPreferences Preferences { get; }
    public NewsService? News { get; set; }
    public VocabularyStore Vocabulary { get; }
    private readonly string? preferencesPath;
    public event Action? Changed;
    public bool Active { get; set; }
    public bool Busy { get; set; }
    public bool Idle { get; set; }
    public string? Failure { get; set; }
    public string? DataMessage { get; set; }
    public string? ShortcutMessage { get; set; }
    public string VoiceName { get; set; } = "Danish neural · offline";
    public bool VoiceReady { get; set; }
    public bool OcrReady { get; set; }
    public bool TranslationReady { get; set; }
    public bool Installing { get; set; }
    public bool ContextReady { get; set; }
    public bool ContextRuntimeReady { get; set; }
    public bool ContextBusy { get; set; }
    public string? ContextMessage { get; set; }
    public Action InstallContext { get; set; } = () => { };
    public Action CheckContext { get; set; } = () => { };
    public Action GetContextRuntime { get; set; } = () => { };
    public Action Toggle { get; set; } = () => { };
    public Action OpenSettings { get; set; } = () => { };
    public Action OpenNews { get; set; } = () => { };
    public Action OpenNewsSettings { get; set; } = () => { };
    public Action OpenReadingControls { get; set; } = () => { };
    public Action OpenBook { get; set; } = () => { };
    public Action Quit { get; set; } = () => { };
    public Action Apply { get; set; } = () => { };
    public Action<string> SelectVoice { get; set; } = _ => { };
    public Action InstallTranslation { get; set; } = () => { };
    public Action InstallVoice { get; set; } = () => { };
    public Action CheckEngines { get; set; } = () => { };
    public Action TryVoice { get; set; } = () => { };
    public Action OpenLanguageSettings { get; set; } = () => { };
    public Action ExportProfile { get; set; } = () => { };
    public Action ImportProfile { get; set; } = () => { };
    public Action ResetProfile { get; set; } = () => { };
    public Action<bool> ShortcutCapture { get; set; } = _ => { };
    public Func<HotKeyConfiguration, string?> ChangeShortcuts { get; set; } = _ => null;
    public ReaderUiModel(ReaderPreferences preferences, VocabularyStore vocabulary, string? preferencesPath = null) { Preferences = preferences; Vocabulary = vocabulary; this.preferencesPath = preferencesPath; }
    public void Notify() => Changed?.Invoke();
    public void Commit() { Preferences.Save(preferencesPath); Apply(); Notify(); }
    public int DueCount => System.Linq.Enumerable.Count(Vocabulary.Saved, e => e.DueAt <= DateTimeOffset.Now);
    public string BookTitle
    {
        get { int count = System.Linq.Enumerable.Count(Vocabulary.Saved); return count == 0 ? "Word Book" : $"Word Book ({count}" + (DueCount > 0 ? $" · {DueCount} to review)" : ")"); }
    }
}
