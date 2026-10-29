using Babelstaarnet.Core;
using Babelstaarnet.Windows;
using System;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

internal static class LanguageSupportChecks
{
    internal static async Task<int> RunAsync(string directory)
    {
        int checks = 0;
        void Check(bool value, string reason) { if (!value) throw new Exception(reason); checks++; }
        ReadingPolicy.CjkTokenizer = CjkWords.Segment;
        using var document = JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Shared", "reading-contract.json")));
        foreach (var item in document.RootElement.GetProperty("languagePairs").EnumerateArray())
        {
            var pair = LanguageCatalog.Pair(item.GetProperty("source").GetString()!, item.GetProperty("target").GetString()!);
            Check(pair.ModelEdges.SequenceEqual(item.GetProperty("models").EnumerateArray().Select(e => e.GetString()!)), "Native model route must match shared vectors.");
            Check(pair.NeedsConversion == item.GetProperty("conversion").GetBoolean(), "Chinese script variants must retain conversion.");
            Check(pair.Legacy || pair.Glosses.Count == 0, "Other language directions must not reuse the Danish→English glossary.");
            string root = pair.ProfileDirectory(directory);
            Check(root == directory == pair.Legacy, "Existing Danish→English data must remain in its original directory.");
            var store = new VocabularyStore(Path.Combine(root, "words.json"), pair); store.Mark(pair.Source.Sample, true, DateTimeOffset.Now);
            Check(JsonDocument.Parse(store.ExportProfile(DateTimeOffset.Now)).RootElement.GetProperty("sourceLanguage").GetString() == pair.Source.Id, "Profile exports carry the selected source language.");
            store.Flush();
            var preferences = new ReaderPreferences { SourceLanguage = pair.Source.Id, TargetLanguage = pair.Target.Id };
            string file = Path.Combine(root, "language-preferences.json"); preferences.Save(file);
            Check(ReaderPreferences.Load(file).LanguagePair == pair, "All 12 directions must survive a restart.");
            using var session = new HoverSession(_ => null, (texts, _) => Task.FromResult<System.Collections.Generic.IReadOnlyList<string>>(texts.Select(_ => "fixture meaning").ToArray()), _ => false, pair);
            var word = new RecognizedWord("får", new(0, 0, 20, 20)); await session.FocusAsync(new(word, new("får", [word])));
            Check(pair.Legacy || session.Meaning == "fixture meaning", "The selected engine supplies other directions, without English table shortcuts.");
        }
        foreach (var item in document.RootElement.GetProperty("multilingualSentences").EnumerateArray())
        {
            string text = item.GetProperty("text").GetString()!;
            Check(SentenceBoundary.StopLocations(text).Count == item.GetProperty("stops").GetInt32(), "Chinese punctuation must split without spaces.");
            Check(SentenceBoundary.EndsSentence(text) == item.GetProperty("ends").GetBoolean(), "Chinese closing quotes belong to the sentence.");
        }
        foreach (string text in new[] { "我喜欢读书。", "我喜歡讀書。" })
        {
            var units = ReadingPolicy.Units(text);
            Check(units.Count >= 3 && units.All(u => text.Substring(u.Index, u.Length) == u.Value), "Use native Chinese word ranges instead of translating a whole clause as one word.");
            Check(ReadingPolicy.Bridge(text, units.ToDictionary(u => ReadingPolicy.Key(u.Value), _ => "help"), _ => true) == text, "Known Chinese text keeps its original spacing and punctuation.");
            var line = CjkWords.SegmentLine(new(text, [new(text, new(10, 20, 100, 20))]));
            Check(line.Words.Count == units.Count && line.Words.All(w => w.Bounds.Width > 0 && w.Bounds.X >= 10 && w.Bounds.Right <= 110), "Chinese word hit regions stay inside the OCR box.");
        }
        var invalid = new ReaderPreferences { SourceLanguage = "../../bad", TargetLanguage = "xx" }; invalid.Normalize();
        Check(invalid.LanguagePair.Legacy, "Invalid preferences cannot become package paths.");
        return checks;
    }
}
