using System.Text.Json;
using System.Text.RegularExpressions;

namespace Babelstaarnet.Core;

public sealed class DanishLanguage
{
    public string[] Abbreviations { get; set; } = [];
    public string[] StructuralWords { get; set; } = [];
    public string[] MeaningPreservationWords { get; set; } = [];
    public Dictionary<string, string> Glosses { get; set; } = [];
    public Dictionary<string, string> Beginner { get; set; } = [];
    public string GlossInstructions { get; set; } = "";
    public string ExplainInstructions { get; set; } = "";
    public static DanishLanguage Shared { get; } = Load();
    private static DanishLanguage Load()
    {
        using var stream = typeof(DanishLanguage).Assembly.GetManifestResourceStream("Babelstaarnet.Core.Danish.json")!;
        return JsonSerializer.Deserialize<DanishLanguage>(stream, new JsonSerializerOptions { PropertyNameCaseInsensitive = true })!;
    }
    public static string Compact(string text) => Regex.Replace(text, @"\s+", " ").Trim();
    public static string Display(string text) => Regex.Replace(Compact(text).Replace('…', '.'), @"\.{2,}", ".");
    public static double KnowledgeOpacity(int level) => 1 - Math.Clamp(level, 0, 5) * .02;
    public static string ConciseMeaning(string meaning, string source)
    {
        string compact = Display(meaning);
        if (ReadingPolicy.Key(compact) == ReadingPolicy.Key(source)) return "";
        var words = compact.Split(' ', StringSplitOptions.RemoveEmptyEntries).Take(12).ToList();
        var dangling = new HashSet<string>(("a am an and are as at be been being by for from in is of or that the to was were with").Split(' '));
        if (compact.Split(' ').Length > 12) while (words.Count > 6 && dangling.Contains(ReadingPolicy.Key(words[^1]))) words.RemoveAt(words.Count - 1);
        return string.Join(' ', words);
    }
}
