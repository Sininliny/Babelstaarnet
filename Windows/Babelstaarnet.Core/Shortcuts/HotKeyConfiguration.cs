namespace Babelstaarnet.Core;

public enum ShortcutAction { ToggleLearning = 1, Known = 2, DontKnow = 3, TogglePin = 4 }
public enum HoldModifier { Alt, Control, Shift, Windows }
public sealed record AppShortcut(uint Key, uint Modifiers)
{
    public bool IsValid => Key is >= 1 and <= 254 && (Modifiers & ~15u) == 0 && Key is not (16 or 17 or 18 or 91 or 92);
    public string Display => ((Modifiers & 2) != 0 ? "Ctrl+" : "") + ((Modifiers & 1) != 0 ? "Alt+" : "") +
        ((Modifiers & 4) != 0 ? "Shift+" : "") + ((Modifiers & 8) != 0 ? "Win+" : "") + KeyName;
    public string KeyName => Key switch
    {
        >= 48 and <= 90 => ((char)Key).ToString(), >= 112 and <= 135 => "F" + (Key - 111),
        32 => "Space", 9 => "Tab", 13 => "Enter", 8 => "Backspace", 46 => "Delete", 27 => "Esc",
        37 => "←", 38 => "↑", 39 => "→", 40 => "↓", 36 => "Home", 35 => "End", 33 => "Page Up", 34 => "Page Down",
        189 => "-", 187 => "=", 188 => ",", 190 => ".", 191 => "/", 186 => ";", 222 => "'", 192 => "`",
        219 => "[", 221 => "]", 220 => "\\", _ => "Key " + Key
    };
}
public sealed record HotKeyConfiguration
{
    public AppShortcut ToggleLearning { get; init; } = new(90, 3);
    public AppShortcut Known { get; init; } = new(49, 0);
    public AppShortcut DontKnow { get; init; } = new(50, 0);
    public AppShortcut TogglePin { get; init; } = new(51, 0);
    public HoldModifier HoldModifier { get; init; } = HoldModifier.Alt;
    public static HotKeyConfiguration Defaults => new();
    public AppShortcut For(ShortcutAction action) => action switch
    { ShortcutAction.ToggleLearning => ToggleLearning, ShortcutAction.Known => Known, ShortcutAction.DontKnow => DontKnow, _ => TogglePin };
    public HotKeyConfiguration With(ShortcutAction action, AppShortcut shortcut) => action switch
    {
        ShortcutAction.ToggleLearning => this with { ToggleLearning = shortcut }, ShortcutAction.Known => this with { Known = shortcut },
        ShortcutAction.DontKnow => this with { DontKnow = shortcut }, _ => this with { TogglePin = shortcut }
    };
    public string? ValidationError()
    {
        if (Enum.GetValues<ShortcutAction>().Any(a => For(a) is null || !For(a).IsValid)) return "That key cannot be used as a shortcut.";
        if (ToggleLearning.Modifiers == 0) return "Toggle hover translation needs at least one modifier key.";
        if (Enum.GetValues<ShortcutAction>().Select(For).Distinct().Count() != 4) return "Each action needs a different shortcut.";
        return Enum.IsDefined(HoldModifier) ? null : "Choose a supported hold modifier.";
    }
    public static string Title(ShortcutAction action) => action switch
    { ShortcutAction.ToggleLearning => "Toggle hover translation", ShortcutAction.Known => "Knew", ShortcutAction.DontKnow => "Don’t know", _ => "Pin or unpin" };
}
