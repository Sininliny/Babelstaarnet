using Babelstaarnet.Windows;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

internal static class AdaptiveNewsChecks
{
    internal static async Task<int> RunAsync(string directory)
    {
        int checks = 0; void Check(bool value, string reason) { if (!value) throw new Exception(reason); checks++; }
        var article = new NewsArticle("airport", "Ukendt lufthavn med lange køer.", "", "https://www.dr.dk/nyheder/fixture", 0, 0);
        using (var reader = new NewsReadingSupport(Path.Combine(directory, "partial-news")))
        {
            reader.WordBands = new Dictionary<string, int> { ["lange"] = 1, ["køer"] = 2 };
            reader.KnowledgeLevel = w => w == "med" ? 4 : 0;
            reader.Translate = (words, _) => Task.FromResult<IReadOnlyList<string>>(words.Select(w => w switch { "lufthavn" => "airport", "lange" => "long", "køer" => "queues", _ => "" }).ToArray());
            await reader.PrepareAsync(article);
            Check(reader.Presentation("lufthavn", article).Text == "airport" && reader.Presentation("køer.", article).Text == "queues.", "One empty result must not discard the other words or punctuation.");
            Check(!reader.Ready(article) && reader.Presentation("Ukendt", article).Mode == 3 && reader.Presentation("lange", article).Mode == 2, "Missing help must stay unresolved; only the ready common word can become a target.");
            await reader.LookupAsync("lange", article);
            Check(reader.Presentation("lange", article).Text == "long" && reader.Selected?.Meaning == "long", "A target's English must be immediately available on request.");
        }
        string cached = Path.Combine(directory, "context-news");
        using (var reader = new NewsReadingSupport(Path.Combine(directory, "staged-news")))
        {
            var longArticle = article with { Title = "ny dag mad vand hus skole arbejde barn familie penge plan" };
            reader.WordBands = new Dictionary<string, int> { ["ny"] = 1 };
            var later = new TaskCompletionSource<IReadOnlyList<string>>(TaskCreationOptions.RunContinuationsAsynchronously); int batches = 0;
            reader.Translate = (words, _) => ++batches == 1 ? Task.FromResult<IReadOnlyList<string>>(words.Select(w => "English " + w).ToArray()) : later.Task;
            var pending = reader.PrepareAsync(longArticle);
            Check(reader.Presentation("ny", longArticle).Text == "…", "Do not show English for a pending target and later withdraw that help.");
            later.SetResult(["English familie", "English penge", "English plan"]); await pending;
            Check(reader.Presentation("ny", longArticle).Mode == 2 && reader.Ready(longArticle), "Publish one complete, stable mixed-reading plan.");
        }
        using (var reader = new NewsReadingSupport(cached))
        {
            reader.CachedWordMeaning = w => w == "køer" ? "cows" : "word";
            reader.ContextualWords = (sentence, words, _) => Task.FromResult<IReadOnlyDictionary<string, string>>(words.ToDictionary(w => w.ToLowerInvariant(), w => w == "køer" ? "queues" : "contextual " + w));
            await reader.PrepareAsync(article);
            Check(reader.Presentation("køer.", article).Text == "queues.", "A sentence meaning must override an isolated cached sense.");
        }
        using (var restored = new NewsReadingSupport(cached))
        {
            restored.ContextualWords = (_, _, _) => throw new Exception("Cached news context must not warm a model again.");
            await restored.PrepareAsync(article);
            Check(restored.Presentation("køer.", article).Text == "queues." && restored.Ready(article), "Article-scoped contextual meanings must survive an offline restart.");
        }
        using (var reader = new NewsReadingSupport(Path.Combine(directory, "stale-news")))
        {
            var reply = new TaskCompletionSource<IReadOnlyDictionary<string, string>>(TaskCreationOptions.RunContinuationsAsynchronously);
            reader.ContextualWords = (_, _, _) => reply.Task;
            var pending = reader.PrepareAsync(article); reader.Cancel();
            reply.SetResult(new Dictionary<string, string> { ["køer"] = "queues" }); await pending;
            Check(!reader.Ready(article) && reader.Selected is null, "A late reply cannot restore a canceled reading plan.");
        }
        using (var news = new NewsService(Path.Combine(directory, "news-ready-gate"), (_, _) => Task.FromResult(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Shared", "news-feed.xml"))), () => DateTimeOffset.Parse("2026-10-22T12:00:00Z")))
        {
            news.Configure(true, true, false, 0, 18); await news.RefreshAsync();
            news.ModelAvailable = () => true; news.ModelIdentity = () => "fixture"; news.SimplifyExcerpt = (source, _) => Task.FromResult(source.Replace(" & ", " og "));
            int shown = 0; news.PresentPopup = _ => { shown++; return true; };
            await news.TickPopupAsync(preview: true);
            Check(shown == 0 && news.PopupStatus.Contains("English support"), "An automatic card must wait for usable mixed-language support instead of showing raw difficult Danish.");
        }
        return checks;
    }
}
