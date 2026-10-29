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
                "news-gloss" => SharedPolicy.bp_news_gloss(I(0),I(1),I(2)),
                "news-reader-band" => SharedPolicy.bp_news_reader_band(I(0),I(1),I(2),I(3)),
                "news-target-budget" => SharedPolicy.bp_news_target_budget(I(0)),
                "news-word-mode" => SharedPolicy.bp_news_word_mode(I(0),I(1),I(2),I(3),I(4),I(5)),
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
        checks += await PopupChecksAsync(directory, xml);
        checks += await ReadingSupportOnOwnerThread(directory, parsed);
        using var session = new HoverSession(_ => "word", (texts, _) => Task.FromResult<System.Collections.Generic.IReadOnlyList<string>>(texts.Select(t => t.Contains(' ') ? "A full sentence." : "word").ToArray()), _ => true);
        var word = new RecognizedWord("ord", new(1,1,10,10)); await session.FocusAsync(new(word, new("Et ord her.", [word])));
        await session.ToggleSentenceMeaningAsync();
        Check(session.SentenceHelp && session.SentenceMeaning == "A full sentence.", "Sentence help must work after background word translation has completed.");
        session.Clear(); Check(!session.SentenceHelp && session.SentenceMeaning.Length == 0, "Sentence help must not leak into another focus.");
        return checks;
    }
    private static async Task<int> PopupChecksAsync(string directory, string xml)
    {
        int checks = 0; void Check(bool ok, string reason) { if (!ok) throw new Exception(reason); checks++; }
        var now = DateTimeOffset.Parse("2026-10-22T12:00:00Z", CultureInfo.InvariantCulture); bool reading = false; int generations = 0, shown = 0;
        string folder = Path.Combine(directory, "scheduled-news");
        using var news = new NewsService(folder, (_, _) => Task.FromResult(xml), () => now);
        news.Configure(true, true, false, 0, 18); await news.RefreshAsync();
        news.ReadingActive = () => reading; news.ModelAvailable = () => true; news.ModelIdentity = () => "fixture-local-model";
        news.Reader.Translate = (texts, _) => Task.FromResult<System.Collections.Generic.IReadOnlyList<string>>(texts.Select(t => "English: " + t).ToArray());
        news.SimplifyExcerpt = (text, _) => { generations++; return Task.FromResult(text.Replace(" & ", " og ")); };
        NewsPopupItem? displayed = null; news.PresentPopup = item => { shown++; displayed = item; return true; };
        await news.TickPopupAsync(); Check(shown == 0 && generations == 0, "Legacy news/background opt-ins must never silently authorize popups.");
        news.ConfigurePopups(true, 60); now = now.AddMinutes(59); await news.TickPopupAsync(); Check(shown == 0, "Enabling cards starts a fresh interval.");
        now = now.AddMinutes(1); reading = true; await news.TickPopupAsync(); Check(generations == 0, "Automatic adaptation must defer to screen reading.");
        reading = false; news.PageVisible = true; await news.TickPopupAsync(); Check(generations == 0, "Do not interrupt someone already reading the news page.");
        news.PageVisible = false; await news.TickPopupAsync();
        Check(shown == 1 && generations == 1 && displayed?.Model == "fixture-local-model" && displayed.Adapted.Title == displayed.Text && displayed.Original.Title != displayed.Text, "Scheduled cards must contain the actual local adaptation, preserving the original separately.");
        await news.TickPopupAsync(); Check(shown == 1, "Minute ticks must never catch up with a burst of cards.");
        using (var restored = new NewsService(folder, (_, _) => throw new Exception("Restart must use cache"), () => now))
            Check(restored.PopupPreferences.Enabled && restored.PopupPreferences.Ids.Length == 1 && !restored.PopupDue() && restored.PopupStatus.Contains("are on"), "Cadence and displayed-story IDs must survive restart.");
        news.PausePopupsForToday(true); now = now.AddHours(1); await news.TickPopupAsync(); Check(shown == 1 && news.PopupsPaused, "Pause today must suppress cards without turning news off.");
        news.PausePopupsForToday(false);
        var pending = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
        news.SimplifyExcerpt = (_, _) => pending.Task;
        var late = news.TickPopupAsync(); news.ConfigurePopups(false, 60); pending.SetResult(news.Cards[1].Article.Title); await late;
        Check(shown == 1 && !news.PopupPreferences.Enabled, "A late model result cannot show a card after the user turns cards off.");
        news.ConfigurePopups(true, 60); now = now.AddHours(1); news.ModelAvailable = () => false; await news.TickPopupAsync();
        Check(shown == 1 && news.PopupStatus.Contains("local AI"), "Missing local AI must never fall back to an unadapted headline.");
        news.Configure(false, true, false, 0, 18); Check(!news.PopupPreferences.Enabled && !news.Preferences.Background, "Disabling news revokes background cards too.");
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
        Check(!reader.IsVisible(headlineOnly), "Danish must be the default reading language.");
        await reader.PrepareAsync(headlineOnly); await reader.PrepareAsync(headlineOnly);
        Check(calls == 1 && reader.Meaning(headlineOnly) is null && !reader.IsVisible(headlineOnly), "Automatic help translates words, never a full English alternative.");
        await reader.PrepareAsync(headlineOnly, true);
        Check(reader.IsVisible(headlineOnly) && calls == 2 && reader.Meaning(headlineOnly)?.Parts.Length == 1, "A direct sentence-help request must give immediate full help, including title-only RSS.");
        reader.HideTranslation(headlineOnly); await reader.PrepareAsync(headlineOnly);
        Check(!reader.IsVisible(headlineOnly) && calls == 2, "Returning to Danish must reuse small hints without re-revealing full English.");
        await reader.PrepareAsync(headlineOnly, true); Check(calls == 2, "Repeated sentence help uses the cache.");
        await reader.LookupAsync("får", headlineOnly); reader.SaveSelection(headlineOnly);
        Check(reader.Selected?.Meaning == "English: får" && saved?.Contains(headlineOnly.Title) == true && spoken == 0, "Lookup/save must preserve Danish context and never autoplay audio.");
        string cacheFile = Path.Combine(folder, "news-reading.json");
        var legacy = System.Text.Json.Nodes.JsonNode.Parse(File.ReadAllText(cacheFile))!; legacy["showEnglish"] = true; File.WriteAllText(cacheFile, legacy.ToJsonString());
        using var restored = new NewsReadingSupport(folder);
        Check(!restored.IsVisible(headlineOnly) && restored.Meaning(headlineOnly) is not null, "Legacy English-on preferences retain cached meanings without revealing them automatically.");
        restored.Translate = (_, _) => throw new Exception("Cached help must not rerun an engine.");
        await restored.PrepareAsync(headlineOnly); await restored.PrepareAsync(headlineOnly, true);
        Check(restored.IsVisible(headlineOnly), "Restarted word and sentence caches must work offline.");
        reader.Cancel(); Check(!reader.IsVisible(headlineOnly), "Closing the reading page resets sentence-help disclosure.");
        var changed = headlineOnly with { Title = headlineOnly.Title + " - updated" };
        Check(restored.Meaning(changed) is null, "A changed headline must not inherit stale English.");
        var pending = new TaskCompletionSource<System.Collections.Generic.IReadOnlyList<string>>(TaskCreationOptions.RunContinuationsAsynchronously);
        reader.Translate = (_, token) => pending.Task.WaitAsync(token);
        var canceled = reader.PrepareAsync(changed, true); reader.Cancel();
        reader.Translate = (texts, _) => Task.FromResult<System.Collections.Generic.IReadOnlyList<string>>(texts.Select(t => "Fresh: " + t).ToArray());
        await reader.PrepareAsync(changed, true); await canceled;
        Check(reader.Meaning(changed)?.Parts[0].StartsWith("Fresh:") == true, "Canceled/stale work must not replace a newer reading aid.");
        var incomplete = changed with { Title = "Incomplete fixture" };
        reader.Translate = (_, _) => Task.FromResult<System.Collections.Generic.IReadOnlyList<string>>([]); await reader.PrepareAsync(incomplete, true);
        Check(reader.Meaning(incomplete) is null && reader.State(incomplete)?.Contains("unavailable") == true, "Failed translation must show help status instead of claiming success.");
        int level = 0; reader.KnowledgeLevel = _ => level; reader.CachedWordMeaning = _ => "hint";
        await reader.PrepareAsync(incomplete); level = 5;
        Check(reader.Gloss("Incomplete", incomplete) == "hint", "Learning elsewhere must not withdraw hints mid-read.");
        reader.Cancel(); await reader.PrepareAsync(incomplete);
        Check(reader.Gloss("Incomplete", incomplete) is null, "A new visit uses the updated knowledge level.");
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
        Check(!Tree(card).OfType<System.Windows.Controls.TextBlock>().Any(t => t.Text.StartsWith("SENTENCE HELP ·")), "The default native card must contain no full English pane.");
        var help = Tree(card).OfType<System.Windows.Controls.Button>().Single(b => Equals(b.Content, "Help with this sentence"));
        help.RaiseEvent(new System.Windows.RoutedEventArgs(System.Windows.Controls.Button.ClickEvent)); card.UpdateSupport();
        Check(localNews.Reader.IsVisible(headlineOnly), "Keyboard-activatable sentence help must remain immediately available.");
        help.RaiseEvent(new System.Windows.RoutedEventArgs(System.Windows.Controls.Button.ClickEvent)); card.UpdateSupport();
        Check(!localNews.Reader.IsVisible(headlineOnly) && Tree(card).Contains(help), "Returning to Danish must preserve the focused help control.");
        var sourceButton = Tree(card).OfType<System.Windows.Controls.Button>().First(b => System.Windows.Automation.AutomationProperties.GetName(b).StartsWith("Look up Danish word "));
        sourceButton.RaiseEvent(new System.Windows.RoutedEventArgs(System.Windows.Controls.Button.ClickEvent));
        Check(localNews.Reader.Selected is { Meaning.Length: > 0 } && localNews.Reader.Selected.Context == headlineOnly.Title, "Native word actions must work directly on source text without OCR or desktop capture.");
        await localNews.Reader.PrepareAsync(headlineOnly, true);
        using (var popupReader = localNews.MakePopupReader())
            Check(localNews.Reader.IsVisible(headlineOnly) && !popupReader.IsVisible(headlineOnly) && popupReader.Meaning(headlineOnly) is not null, "A popup shares cached answers but never inherits the book's revealed English state.");
        bool dismissed = false;
        var item = new NewsPopupItem(headlineOnly, "En ny park.", "fixture-local-model");
        var popup = new NewsPopupWindow(localNews, item, () => { });
        Check(!popup.ShowActivated && !popup.ShowInTaskbar && !popup.IsVisible, "Creating a news popup must never activate or display a test window."); popup.Close();
        var panel = new NewsPopupPanel(localNews, item, () => dismissed = true, () => { });
        Tree(panel).OfType<System.Windows.Controls.Button>().Single(b => Equals(b.Content, "Turn off")).RaiseEvent(new System.Windows.RoutedEventArgs(System.Windows.Controls.Button.ClickEvent));
        Check(dismissed && !localNews.PopupPreferences.Enabled, "The popup must offer a direct turn-off action without a settings detour.");
        localNews.SimplifyExcerpt = (source, _) => Task.FromResult(source); await localNews.SimplifyAsync(headlineOnly);
        Check(localNews.Simplified(headlineOnly) == headlineOnly.Title, "Title-only news must also support optional local plain Danish.");
        return checks;
    }
}
