using Babelstaarnet.Core;
using Babelstaarnet.Windows;
using System;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

internal static class SharedPolicyChecks
{
    internal static async Task<int> RunAsync(string directory)
    {
        int checks = 0;
        void Check(bool value, string message) { if (!value) throw new Exception(message); checks++; }
        Check(SharedPolicy.bp_version() == 1, "Native shared ABI must be packaged with the client.");
        using var json = JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Shared", "policy-runtime.json")));
        foreach (var c in json.RootElement.GetProperty("cases").EnumerateArray())
        {
            var a = c.GetProperty("args").EnumerateArray().ToArray(); int I(int n) => a[n].GetInt32(); double D(int n) => a[n].GetDouble(); string S(int n) => a[n].GetString()!;
            double result = c.GetProperty("operation").GetString() switch
            {
                "anchor" => SharedPolicy.bp_anchor(I(0),I(1),I(2),I(3),I(4),I(5)),
                "challenge" => SharedPolicy.bp_challenge(I(0),I(1),I(2),I(3),I(4),I(5)),
                "fetch" => SharedPolicy.bp_fetch(I(0),I(1),I(2),I(3),D(4),D(5)),
                "digest" => SharedPolicy.bp_digest(I(0),I(1),I(2),I(3),I(4),I(5),I(6),I(7)),
                "evidence" => SharedPolicy.bp_evidence(I(0),I(1),I(2)),
                "rewrite" => SharedPolicy.bp_rewrite(I(0),I(1),I(2),I(3),I(4)),
                "score" => SharedPolicy.bp_news_score(D(0),D(1),D(2),D(3),I(4)),
                "contains" => SharedPolicy.Contains(S(0),S(1)) ? 1 : 0,
                "story" => SharedPolicy.SameStory(S(0),S(1)) ? 1 : 0,
                _ => throw new Exception("Unknown shared policy vector")
            };
            Check(Math.Abs(result - c.GetProperty("expected").GetDouble()) < .000001, "Shared policy vector " + c.GetProperty("id").GetString());
        }
        string xml = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Shared", "news-feed.xml"));
        var parsed = NewsService.ParseFeed(xml, 0);
        Check(parsed.Length == 3 && parsed[0].Summary == "En kort & tydelig besked.", "RSS must render bounded plain text and reject external URLs and missing dates.");
        bool rejected = false; try { NewsService.ParseFeed("<!DOCTYPE rss [<!ENTITY x SYSTEM 'file:///private'>]><rss/>", 0); } catch (System.Xml.XmlException) { rejected = true; }
        Check(rejected, "RSS entities must never read a local file.");
        int downloads = 0; var now = DateTimeOffset.Parse("2026-10-22T12:00:00Z", CultureInfo.InvariantCulture);
        using var news = new NewsService(Path.Combine(directory, "news"), (_, _) => { downloads++; return Task.FromResult(xml); }, () => now);
        news.LearningUnits = () => ["energi", "æbler"];
        await news.RefreshAsync(true);
        Check(downloads == 0, "Opening or refreshing news while disabled must make zero requests.");
        news.Configure(true, false, false, 0, 18); await news.RefreshAsync();
        Check(downloads == 1 && news.Cards.Count == 2 && news.Cards.Any(c => c.Matches.Contains("æbler")), "Opt-in RSS uses local learning matching and deduplicates stories.");
        await news.RefreshAsync(); Check(downloads == 1, "Fresh cache must avoid another request.");
        var first = news.Cards[0].Article; news.MarkSeen(first); Check(!news.Cards.Any(c => SharedPolicy.SameStory(c.Article.Title, first.Title)), "Already seen hides equivalent stories.");
        news.Configure(false, true, true, 0, 18); now = now.AddHours(8); await news.RefreshAsync(true, true);
        Check(downloads == 1 && !news.Preferences.Background && !news.Preferences.Notify, "Disable news cancels all background privileges.");
        using var reloaded = new NewsService(Path.Combine(directory, "news"), (_, _) => throw new Exception("Offline cache accessed network"), () => now);
        Check(!reloaded.Preferences.Enabled && reloaded.Cards.Count > 0, "Cache remains usable offline across restart.");
        using var session = new HoverSession(_ => "word", (texts, _) => Task.FromResult<System.Collections.Generic.IReadOnlyList<string>>(texts.Select(t => t.Contains(' ') ? "A full sentence." : "word").ToArray()), _ => true);
        var word = new RecognizedWord("ord", new(1,1,10,10)); await session.FocusAsync(new(word, new("Et ord her.", [word])));
        await session.ToggleSentenceMeaningAsync();
        Check(session.SentenceHelp && session.SentenceMeaning == "A full sentence.", "Sentence help must work after background word translation has completed.");
        session.Clear(); Check(!session.SentenceHelp && session.SentenceMeaning.Length == 0, "Sentence help must not leak into another focus.");
        return checks;
    }
}
