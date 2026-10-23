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
                "reading-help" => SharedPolicy.bp_reading_help(I(0),I(1),I(2),I(3)),
                "retry" => SharedPolicy.bp_retry_delay(I(0)),
                "source" => SharedPolicy.bp_source_capability(I(0)),
                "summary" => SharedPolicy.SummaryValid(S(0),S(1), DanishLanguage.Shared.MeaningPreservationWords) ? 1 : 0,
                "target" => SharedPolicy.bp_target_allowed(I(0),I(1)),
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
        news.MeaningPreservationWords = DanishLanguage.Shared.MeaningPreservationWords;
        int generations = 0; bool reading = true;
        news.ReadingActive = () => reading;
        news.ModelAvailable = () => true; news.ModelIdentity = () => "fixture-v1";
        news.SimplifyExcerpt = (text, _) => { generations++; return Task.FromResult("En tydelig besked."); };
        var excerpt = parsed[0]; await news.SimplifyAsync(excerpt);
        Check(generations == 0 && news.Simplified(excerpt) is null, "Active screen reading must defer news inference.");
        reading = false; await news.SimplifyAsync(excerpt); await news.SimplifyAsync(excerpt);
        Check(generations == 1 && news.Simplified(excerpt) == "En tydelig besked." && news.SimplifiedModel(excerpt) == "fixture-v1", "Local excerpt simplification must be cached and labelled with its model.");
        using (var restored = new NewsService(Path.Combine(directory, "news")))
        { restored.MeaningPreservationWords = news.MeaningPreservationWords; Check(restored.Simplified(excerpt) == "En tydelig besked.", "AI excerpt metadata survives restart without inference or HTTP."); }
        news.Configure(true, true, true, 0, 18); now = now.AddHours(6);
        Check(news.DigestDue(false, true) && !news.DigestDue(true, true) && !news.DigestDue(false, false), "News digest requires idle reading and actual notification permission.");
        news.PageVisible = true; Check(!news.DigestDue(false, true), "An open news page suppresses digests.");
        int before = downloads; await news.RefreshAsync(background: true); Check(downloads == before, "Background refresh must not replace visible reading cards."); news.PageVisible = false;
        string notified = news.DigestCandidates[0].Id; news.DigestSent();
        Check(!news.DigestDue(false, true), "Digest is limited to one per local day.");
        now = now.AddDays(1); Check(!news.DigestCandidates.Any(a => a.Id == notified), "A headline must not be notified again the next day.");
        var first = news.Cards[0].Article; news.MarkSeen(first); Check(!news.Cards.Any(c => SharedPolicy.SameStory(c.Article.Title, first.Title)), "Already seen hides equivalent stories.");
        news.Configure(false, true, true, 0, 18); now = now.AddHours(8); await news.RefreshAsync(true, true);
        Check(downloads == 1 && !news.Preferences.Background && !news.Preferences.Notify, "Disable news cancels all background privileges.");
        using var reloaded = new NewsService(Path.Combine(directory, "news"), (_, _) => throw new Exception("Offline cache accessed network"), () => now);
        Check(!reloaded.Preferences.Enabled && reloaded.Cards.Count > 0, "Cache remains usable offline across restart.");
        string legacy = Path.Combine(directory, "legacy-shortcuts.json");
        File.WriteAllText(legacy, "{\"Shortcuts\":{\"Known\":{\"Key\":52,\"Modifiers\":0}}}");
        var migrated = ReaderPreferences.Load(legacy);
        Check(migrated.Shortcuts.Known == new AppShortcut(52, 0) && migrated.Shortcuts.SentenceMeaning != migrated.Shortcuts.Known && migrated.Shortcuts.ValidationError() is null, "Adding sentence help must preserve legacy shortcut choices.");
        var evidence = new VocabularyStore(Path.Combine(directory, "evidence.json")); evidence.Save("æbler", "apples", "Jeg spiser æbler.", now); evidence.Mark("æbler", true, now);
        Check(evidence.Saved.Single().LastEvidenceKind == 2, "Knew is self-report, not verified recall.");
        checks += await ReadingSupportOnOwnerThread(directory, parsed);
        using var session = new HoverSession(_ => "word", (texts, _) => Task.FromResult<System.Collections.Generic.IReadOnlyList<string>>(texts.Select(t => t.Contains(' ') ? "A full sentence." : "word").ToArray()), _ => true);
        var word = new RecognizedWord("ord", new(1,1,10,10)); await session.FocusAsync(new(word, new("Et ord her.", [word])));
        await session.ToggleSentenceMeaningAsync();
        Check(session.SentenceHelp && session.SentenceMeaning == "A full sentence.", "Sentence help must work after background word translation has completed.");
        session.Clear(); Check(!session.SentenceHelp && session.SentenceMeaning.Length == 0, "Sentence help must not leak into another focus.");
        return checks;
    }
    private static Task<int> ReadingSupportOnOwnerThread(string directory, NewsArticle[] articles)
    {
        var result = new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously);
        var thread = new Thread(() =>
        {
            var dispatcher = System.Windows.Threading.Dispatcher.CurrentDispatcher;
            SynchronizationContext.SetSynchronizationContext(new System.Windows.Threading.DispatcherSynchronizationContext(dispatcher));
            async void Start()
            {
                try { result.SetResult(await ReadingSupportAsync(directory, articles)); }
                catch (Exception error) { result.SetException(error); }
                finally { dispatcher.BeginInvokeShutdown(System.Windows.Threading.DispatcherPriority.Background); }
            }
            dispatcher.BeginInvoke(new Action(Start)); System.Windows.Threading.Dispatcher.Run();
        });
        thread.SetApartmentState(ApartmentState.STA); thread.Start(); return result.Task;
    }
    private static async Task<int> ReadingSupportAsync(string directory, NewsArticle[] articles)
    {
        int checks = 0; void Check(bool value, string message) { if (!value) throw new Exception(message); checks++; }
        string folder = Path.Combine(directory, "beginner-news");
        using var reader = new NewsReadingSupport(folder); int calls = 0, spoken = 0; string? saved = null;
        reader.Translate = (texts, _) => { calls++; return Task.FromResult<System.Collections.Generic.IReadOnlyList<string>>(texts.Select(t => "English: " + t).ToArray()); };
        reader.Speak = _ => spoken++; reader.SaveWord = (word, meaning, context) => saved = word + "|" + meaning + "|" + context;
        var headlineOnly = articles.First(a => a.Summary.Length == 0);
        Check(reader.ShowEnglish, "Beginners must receive English support by default, including old preference files.");
        await reader.PrepareAsync(headlineOnly); await reader.PrepareAsync(headlineOnly);
        Check(calls == 1 && reader.Meaning(headlineOnly)?.Parts.Length == 1, "A title-only RSS item must still get English, cached without another request.");
        reader.SetEnglish(false); Check(!reader.IsVisible(headlineOnly), "Trying Danish first must hide English voluntarily.");
        await reader.PrepareAsync(headlineOnly); Check(calls == 1, "Danish-first mode must not start hidden work.");
        await reader.PrepareAsync(headlineOnly, true); Check(reader.IsVisible(headlineOnly) && calls == 1, "Explicit help bypasses the practice preference and uses cached English.");
        await reader.LookupAsync("får", headlineOnly); reader.SaveSelection(headlineOnly);
        Check(reader.Selected?.Meaning == "English: får" && saved?.Contains(headlineOnly.Title) == true && spoken == 0, "Lookup/save must preserve Danish context and never autoplay audio.");
        using var restored = new NewsReadingSupport(folder);
        Check(!restored.ShowEnglish && restored.Meaning(headlineOnly) is not null, "English and reading mode must survive restart without any network adapter.");
        var changed = headlineOnly with { Title = headlineOnly.Title + " - updated" };
        Check(restored.Meaning(changed) is null, "A changed headline must not inherit stale English.");
        reader.SetEnglish(true); var pending = new TaskCompletionSource<System.Collections.Generic.IReadOnlyList<string>>(TaskCreationOptions.RunContinuationsAsynchronously);
        reader.Translate = (_, token) => pending.Task.WaitAsync(token);
        var canceled = reader.PrepareAsync(changed); reader.Cancel();
        reader.Translate = (texts, _) => Task.FromResult<System.Collections.Generic.IReadOnlyList<string>>(texts.Select(t => "Fresh: " + t).ToArray());
        await reader.PrepareAsync(changed); await canceled;
        Check(reader.Meaning(changed)?.Parts[0].StartsWith("Fresh:") == true, "Canceled/stale work must not replace a newer reading aid.");
        var incomplete = changed with { Title = "Incomplete fixture" };
        reader.Translate = (_, _) => Task.FromResult<System.Collections.Generic.IReadOnlyList<string>>([]); await reader.PrepareAsync(incomplete);
        Check(reader.Meaning(incomplete) is null && reader.State(incomplete)?.Contains("unavailable") == true, "Failed translation must show help status instead of claiming success.");
        using var localNews = new NewsService(Path.Combine(directory, "card-actions"));
        localNews.Reader.Translate = (texts, _) => Task.FromResult<System.Collections.Generic.IReadOnlyList<string>>(texts.Select(t => "English: " + t).ToArray());
        localNews.Reader.Speak = _ => throw new Exception("No automatic audio is allowed.");
        await localNews.Reader.PrepareAsync(headlineOnly);
        var card = new NewsReadingCard(localNews, new NewsCard(headlineOnly, [], .5));
        System.Collections.Generic.IEnumerable<System.Windows.DependencyObject> Tree(System.Windows.DependencyObject node)
        {
            yield return node;
            foreach (var child in System.Windows.LogicalTreeHelper.GetChildren(node).OfType<System.Windows.DependencyObject>())
                foreach (var nested in Tree(child)) yield return nested;
        }
        var sourceButton = Tree(card).OfType<System.Windows.Controls.Button>().First(b => System.Windows.Automation.AutomationProperties.GetName(b).StartsWith("Look up Danish word "));
        sourceButton.RaiseEvent(new System.Windows.RoutedEventArgs(System.Windows.Controls.Button.ClickEvent));
        Check(localNews.Reader.Selected is { Meaning.Length: > 0 } && localNews.Reader.Selected.Context == headlineOnly.Title, "Native word actions must work directly on source text without OCR or desktop capture.");
        localNews.SimplifyExcerpt = (source, _) => Task.FromResult(source); await localNews.SimplifyAsync(headlineOnly);
        Check(localNews.Simplified(headlineOnly) == headlineOnly.Title, "Title-only news must also support optional local plain Danish.");
        return checks;
    }
}
