using Babelstaarnet.Core;
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Xml;
using System.Xml.Linq;

namespace Babelstaarnet.Windows;

internal sealed record NewsArticle(string Id, string Title, string Summary, string Url, double Published, int Topic);
internal sealed record NewsCard(NewsArticle Article, string[] Matches, double Score);
internal sealed record NewsShortVersion(string Text, string Model, double Created);
internal sealed class NewsPopupPreferences
{
    public bool Enabled { get; set; }
    public int IntervalMinutes { get; set; } = 120;
    public double? LastShown { get; set; }
    public string? Day { get; set; }
    public int Shown { get; set; }
    public string[] Ids { get; set; } = [];
    public double? PausedUntil { get; set; }
}
internal sealed record NewsPopupItem(NewsArticle Original, string Text, string Model, bool Preview = false)
{
    public NewsArticle Adapted => Original with { Title = Text, Summary = "" };
}
internal sealed class NewsPreferences
{
    public NewsPopupPreferences? Popup { get; set; }
    public bool Enabled { get; set; }
    public bool Background { get; set; }
    public bool Notify { get; set; }
    public int Topic { get; set; }
    public int DigestHour { get; set; } = 18;
    public string? LastDigestDay { get; set; }
    public string[] LastDigestIds { get; set; } = [];
    public int LastBookPage { get; set; }
}
internal sealed class NewsCache
{
    public double Fetched { get; set; }
    public int Topic { get; set; }
    public NewsArticle[] Articles { get; set; } = [];
    public Dictionary<string, double> Seen { get; set; } = [];
    public Dictionary<string, double> SeenTitles { get; set; } = [];
    public Dictionary<string, NewsShortVersion> ShortVersions { get; set; } = [];
}

// DR metadata only. No browser engine, remote assets, personalized request or cloud fallback.
// Source guide: https://www.dr.dk/nyheder/dr-nyheder-som-rss-feed (verified 2026-10-22).
internal sealed class NewsService : IDisposable
{
    public NewsReadingSupport Reader { get; }
    public static readonly string[] Topics = ["Latest", "Denmark", "World", "Money", "Politics", "Science", "Culture", "Sport"];
    public const string Disclosure = "Connects to DR to fetch public news. Matching stays on this PC. No word list, screenshots or learning records are uploaded. DR receives ordinary requests, including your IP address and requested URLs. Opening an original uses your browser.";
    private static readonly JsonSerializerOptions Json = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
    private readonly string preferencesPath, cachePath;
    private readonly Func<Uri, CancellationToken, Task<string>> download;
    private readonly Func<DateTimeOffset> clock;
    private readonly HttpClient? http;
    private CancellationTokenSource? fetch;
    private DateTimeOffset? lastAttempt;
    private DateTimeOffset? nextRetry;
    private int failedRequests;
    private NewsCache cache;
    private bool disposed;
    private int rotation;
    private CancellationTokenSource? generation;
    private readonly Dictionary<string, NewsShortVersion> simplified = [];
    private readonly Dictionary<string, string> simplificationStates = [];
    public Func<string, CancellationToken, Task<string>>? SimplifyExcerpt { get; set; }
    public Func<bool>? ModelAvailable { get; set; }
    public Func<string> ModelIdentity { get; set; } = () => "Local language model";
    public string[] MeaningPreservationWords { get; set; } = [];
    public string LanguageInstructions { get; set; } = "";
    public Func<bool> ReadingActive { get; set; } = () => false;
    public string PopupStatus { get; private set; } = "Scheduled cards are off.";
    public bool PopupVisible { get; set; }
    public Func<bool> PopupAllowed { get; set; } = () => true;
    public Func<NewsPopupItem, bool>? PresentPopup { get; set; }
    private bool popupPreparing;
    private Guid popupRevision = Guid.NewGuid();
    private DateTimeOffset? popupRetry;
    public NewsPopupPreferences PopupPreferences => Preferences.Popup ?? new();
    public bool PopupsPaused => (PopupPreferences.PausedUntil ?? 0) > clock().ToUnixTimeSeconds();
    public bool PageVisible { get; set; }
    public bool HasUpdates { get; private set; }
    public NewsPreferences Preferences { get; }
    public bool Busy { get; private set; }
    public string Status { get; private set; } = "News is optional. Enable it to connect to DR.";
    public IReadOnlyList<NewsCard> Cards { get; private set; } = [];
    public event Action? Changed;
    public Func<IEnumerable<string>> LearningUnits { get; set; } = () => [];
    public NewsService(string directory, Func<Uri, CancellationToken, Task<string>>? download = null, Func<DateTimeOffset>? clock = null)
    {
        this.clock = clock ?? (() => DateTimeOffset.Now);
        Reader = new NewsReadingSupport(directory) { BeforeHelp = CancelGeneration };
        preferencesPath = Path.Combine(directory, "news-preferences.json"); cachePath = Path.Combine(directory, "news-cache.json");
        Preferences = Load<NewsPreferences>(preferencesPath) ?? new(); cache = Load<NewsCache>(cachePath) ?? new();
        Preferences.Topic = Math.Clamp(Preferences.Topic, 0, Topics.Length - 1); Preferences.DigestHour = Math.Clamp(Preferences.DigestHour, 9, 20);
        if (!Preferences.Enabled) Preferences.Background = Preferences.Notify = false;
        if (!Preferences.Background) { Preferences.Notify = false; if (Preferences.Popup is { } disabled) disabled.Enabled = false; }
        if (Preferences.Popup is { } popup)
        {
            if (!new[] { 60, 120, 240 }.Contains(popup.IntervalMinutes)) popup.IntervalMinutes = 120;
            popup.Shown = Math.Clamp(popup.Shown, 0, 3); popup.Ids = (popup.Ids ?? []).Where(s => s is not null && s.Length < 512).TakeLast(100).ToArray();
            if (popup.LastShown is { } at && (!double.IsFinite(at) || at > this.clock().ToUnixTimeSeconds())) popup.LastShown = this.clock().ToUnixTimeSeconds();
            if (popup.PausedUntil is { } until && (!double.IsFinite(until) || until > this.clock().ToUnixTimeSeconds() + 86400)) popup.PausedUntil = null;
        }
        Preferences.LastDigestIds ??= [];
        cache.Articles ??= []; cache.Seen ??= []; cache.SeenTitles ??= [];
        cache.ShortVersions ??= [];
        foreach (var pair in cache.ShortVersions.Where(p => p.Key.Length < 1000 && p.Value?.Text is { Length: > 0 and <= 3000 } && p.Value.Model is { Length: <= 200 } && double.IsFinite(p.Value.Created)).OrderBy(p => p.Key, StringComparer.Ordinal).Take(64)) simplified[pair.Key] = pair.Value;
        cache.Articles = cache.Articles.Where(ValidArticle).Take(256).ToArray();
        if (!double.IsFinite(cache.Fetched) || cache.Fetched < 0 || cache.Fetched > this.clock().ToUnixTimeSeconds() + 3600) cache.Fetched = 0;
        if (download is null)
        {
            http = new(new SocketsHttpHandler { AllowAutoRedirect = false, UseCookies = false }) { Timeout = TimeSpan.FromSeconds(15) };
            http.DefaultRequestHeaders.UserAgent.ParseAdd("Babelstaarnet/0.6.4");
            this.download = DownloadAsync;
        }
        else this.download = download;
        PopupStatus = PopupPreferences.Enabled ? (PopupsPaused ? "News cards are paused for today." : "Scheduled cards are on.") : "Scheduled cards are off.";
        SelectCards();
    }
    private static T? Load<T>(string path) { try { return new FileInfo(path).Length <= 2_000_000 ? JsonSerializer.Deserialize<T>(File.ReadAllText(path), Json) : default; } catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException) { return default; } }
    private void Save()
    {
        try
        {
        Directory.CreateDirectory(Path.GetDirectoryName(preferencesPath)!);
        void Write(string path, object value) { string temp = path + ".tmp"; File.WriteAllText(temp, JsonSerializer.Serialize(value, Json)); File.Move(temp, path, true); }
        Write(preferencesPath, Preferences); Write(cachePath, cache);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { Status = "News changes could not be saved: " + e.Message; }
    }
    public void Configure(bool enabled, bool background, bool notify, int topic, int hour)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        bool changedTopic = Preferences.Topic != topic;
        Preferences.Enabled = enabled; Preferences.Background = enabled && background; Preferences.Notify = enabled && background && notify;
        Preferences.Topic = Math.Clamp(topic, 0, Topics.Length - 1); Preferences.DigestHour = Math.Clamp(hour, 9, 20);
        if (!enabled || changedTopic) { fetch?.Cancel(); CancelGeneration(); rotation = 0; }
        if (changedTopic) { nextRetry = null; failedRequests = 0; }
        if (!enabled) { Preferences.Background = Preferences.Notify = false; Status = "News is off. Cached articles remain available offline."; }
        if ((!enabled || !background || notify) && Preferences.Popup is { } popup) { popup.Enabled = false; popupRevision = Guid.NewGuid(); }
        if (changedTopic) popupRevision = Guid.NewGuid();
        Save(); SelectCards(); Changed?.Invoke();
    }
    public async Task RefreshAsync(bool manual = false, bool background = false)
    {
        if (disposed || Busy || background && PageVisible) return;
        var now = clock();
        if (!manual && nextRetry is { } retry && now < retry) return;
        double successAge = cache.Topic == Preferences.Topic && cache.Fetched > 0 ? now.ToUnixTimeSeconds() - cache.Fetched : -1;
        if (SharedPolicy.bp_fetch(Preferences.Enabled ? 1 : 0, Preferences.Background ? 1 : 0, background ? 1 : 0, manual ? 1 : 0,
            lastAttempt is { } attempted ? (now - attempted).TotalSeconds : -1, successAge) == 0)
        { if (manual && Preferences.Enabled && lastAttempt is { } last && now - last < TimeSpan.FromSeconds(60)) { Status = "Recently refreshed. Try again in a minute."; Changed?.Invoke(); } return; }
        lastAttempt = now; Busy = true; Status = "Fetching public headlines from DR…"; Changed?.Invoke();
        using var request = new CancellationTokenSource(); fetch = request; int topic = Preferences.Topic;
        try
        {
            string xml = await download(new(SharedPolicy.FeedUrl(topic)), request.Token);
            request.Token.ThrowIfCancellationRequested(); if (!Preferences.Enabled || topic != Preferences.Topic || disposed) return;
            var articles = ParseFeed(xml, topic);
            if (articles.Length == 0) throw new InvalidDataException("DR returned no usable news entries.");
            cache.Articles = articles; cache.Topic = topic; cache.Fetched = now.ToUnixTimeSeconds(); rotation = 0;
            failedRequests = 0; nextRetry = null;
            Status = "Updated from DR · " + now.ToString("g"); Save();
            if (Cards.Count == 0 || manual || !PageVisible) SelectCards(); else HasUpdates = true;
        }
        catch (OperationCanceledException) when (request.IsCancellationRequested) { }
        catch (Exception e) when (e is HttpRequestException or IOException or XmlException or TaskCanceledException or InvalidOperationException)
        { failedRequests = Math.Min(16, failedRequests + 1); nextRetry = clock().AddSeconds(SharedPolicy.bp_retry_delay(failedRequests)); Status = "News could not be updated. Cached content is available. " + e.Message; }
        finally { if (ReferenceEquals(fetch, request)) fetch = null; Busy = false; if (!disposed) Changed?.Invoke(); }
    }
    private async Task<string> DownloadAsync(Uri uri, CancellationToken token)
    {
        if (!Preferences.Enabled || uri.AbsoluteUri != SharedPolicy.FeedUrl(Preferences.Topic)) throw new OperationCanceledException(token);
        using var response = await http!.GetAsync(uri, HttpCompletionOption.ResponseHeadersRead, token); response.EnsureSuccessStatusCode();
        if (response.Content.Headers.ContentLength > 1_000_000) throw new InvalidDataException("News response is too large.");
        using var stream = await response.Content.ReadAsStreamAsync(token); using var bytes = new MemoryStream(); byte[] buffer = new byte[8192];
        int count; while ((count = await stream.ReadAsync(buffer, token)) > 0) { if (bytes.Length + count > 1_000_000) throw new InvalidDataException("News response is too large."); await bytes.WriteAsync(buffer.AsMemory(0, count), token); }
        return System.Text.Encoding.UTF8.GetString(bytes.ToArray());
    }
    internal static NewsArticle[] ParseFeed(string xml, int topic)
    {
        if (xml.Length > 1_000_000) throw new InvalidDataException("News response is too large.");
        using var input = new StringReader(xml); using var reader = XmlReader.Create(input, new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null, MaxCharactersInDocument = 1_000_000 });
        var document = XDocument.Load(reader); var result = new List<NewsArticle>();
        foreach (var item in document.Descendants("item").Take(128))
        {
            string Get(string key) => item.Elements().FirstOrDefault(e => e.Name.LocalName == key)?.Value ?? "";
            if (!DateTimeOffset.TryParse(Get("pubDate"), CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var published)) continue;
            var article = new NewsArticle(Get("guid"), Plain(Get("title"), 350), Plain(Get("description"), 3000), Get("link").Trim(), published.ToUnixTimeSeconds(), topic);
            if (ValidArticle(article)) result.Add(article with { Id = article.Id.Length is > 0 and < 512 ? article.Id : article.Url });
        }
        return result.DistinctBy(a => a.Url).ToArray();
    }
    private static string Plain(string input, int limit)
    {
        string text = Regex.Replace(WebUtility.HtmlDecode(input), "<[^>]*>", " "); text = Regex.Replace(text, @"\s+", " ").Trim();
        text = Regex.Replace(text, @"\s+([.,;:!?])", "$1");
        return text[..Math.Min(text.Length, limit)];
    }
    internal static bool ValidArticle(NewsArticle? a) => a is not null && !string.IsNullOrWhiteSpace(a.Title) && a.Title.Length <= 350 && a.Summary is not null && a.Summary.Length <= 3000 && a.Id is not null && a.Id.Length < 512 &&
        Uri.TryCreate(a.Url, UriKind.Absolute, out var url) && url.Scheme == "https" && url.Host == "www.dr.dk" && url.UserInfo.Length == 0 && url.Port == 443 && url.AbsolutePath.StartsWith("/nyheder/", StringComparison.Ordinal) && double.IsFinite(a.Published) && a.Topic is >= 0 and < 8;
    public void NextGroup() { rotation += 3; HasUpdates = false; SelectCards(); Changed?.Invoke(); }
    public void AcceptUpdates() { rotation = 0; HasUpdates = false; SelectCards(); Changed?.Invoke(); }
    public void SetBookPage(int page) { Preferences.LastBookPage = Math.Clamp(page, 0, 1); Save(); }
    private static string ExcerptText(NewsArticle a) => a.Summary.Length == 0 ? a.Title : a.Summary;
    private string ExcerptKey(NewsArticle a) => a.Id + ":v1:" + Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(ExcerptText(a) + "\u001f" + SharedPolicy.RewritePrompt + "\u001f" + LanguageInstructions + "\u001f" + string.Join('\n', MeaningPreservationWords))));
    public string? Simplified(NewsArticle a) => simplified.GetValueOrDefault(ExcerptKey(a))?.Text;
    public string? SimplifiedModel(NewsArticle a) => simplified.GetValueOrDefault(ExcerptKey(a))?.Model;
    public string? SimplificationState(NewsArticle a) => simplificationStates.GetValueOrDefault(ExcerptKey(a));
    public async Task SimplifyAsync(NewsArticle article)
    {
        // Only the public RSS excerpt supplied by DR, never fetched full article text.
        string key = ExcerptKey(article);
        if (simplified.ContainsKey(key)) return;
        int decision = SharedPolicy.bp_rewrite(SharedPolicy.bp_source_capability(2), ExcerptText(article).Length > 0 ? 1 : 0, (ModelAvailable?.Invoke() ?? SimplifyExcerpt is not null) ? 1 : 0, ReadingActive() ? 1 : 0, 0);
        if (decision != 1) { simplificationStates[key] = decision == 2 ? "Pause screen reading to simplify this excerpt. The original remains available." : "Install the optional local language model to simplify RSS excerpts."; Changed?.Invoke(); return; }
        if (generation is not null) return;
        using var request = new CancellationTokenSource(TimeSpan.FromSeconds(90)); generation = request;
        simplificationStates[key] = "Simplifying this RSS excerpt locally…"; Changed?.Invoke();
        try
        {
            string text = await SimplifyExcerpt!(ExcerptText(article), request.Token); request.Token.ThrowIfCancellationRequested();
            if (!SharedPolicy.SummaryValid(ExcerptText(article), text, MeaningPreservationWords)) throw new InvalidDataException("Short version did not pass the conservative checks. Read the original excerpt instead.");
            if (simplified.Count >= 64) simplified.Clear();
            simplified[key] = new(text, ModelIdentity(), clock().ToUnixTimeSeconds()); simplificationStates.Remove(key); cache.ShortVersions = new(simplified); Save();
        }
        catch (OperationCanceledException) { simplificationStates[key] = "Short version canceled; the original excerpt remains available."; }
        catch (Exception e) { simplificationStates[key] = e.Message; }
        finally { if (ReferenceEquals(generation, request)) generation = null; if (!disposed) Changed?.Invoke(); }
    }
    public void CancelGeneration() => generation?.Cancel();
    public void MarkSeen(NewsArticle article)
    {
        cache.Seen[article.Id] = clock().ToUnixTimeSeconds(); cache.SeenTitles[article.Title] = clock().ToUnixTimeSeconds();
        cache.SeenTitles = cache.SeenTitles.Where(p => clock().ToUnixTimeSeconds() - p.Value <= 604800).TakeLast(100).ToDictionary(p => p.Key, p => p.Value);
        cache.Seen = cache.Seen.Where(p => clock().ToUnixTimeSeconds() - p.Value <= 604800).TakeLast(256).ToDictionary(p => p.Key, p => p.Value);
        Save(); SelectCards(); Changed?.Invoke();
    }
    public void SelectCards()
    {
        var now = clock(); var units = LearningUnits().Select(s => s.Normalize().ToLowerInvariant()).Where(s => !ReadingPolicy.StructuralWords.Contains(s)).Distinct().Order(StringComparer.Ordinal).Take(200).ToArray();
        var ranked = cache.Articles.Where(a => ValidArticle(a) && a.Topic == Preferences.Topic).Select(a =>
        {
            string[] matches = units.Where(w => SharedPolicy.Contains(a.Title + " " + a.Summary, w)).Take(5).ToArray();
            bool seen = cache.Seen.TryGetValue(a.Id, out double at) && now.ToUnixTimeSeconds() - at <= 604800 || cache.SeenTitles.Any(p => now.ToUnixTimeSeconds() - p.Value <= 604800 && SharedPolicy.SameStory(a.Title, p.Key));
            return new NewsCard(a, matches, SharedPolicy.bp_news_score((now.ToUnixTimeSeconds() - a.Published) / 3600, .5, matches.Length * .25, .5, seen ? 1 : 0));
        }).Where(c => c.Score >= 0).OrderByDescending(c => c.Score).ThenByDescending(c => c.Article.Published).ThenBy(c => c.Article.Id, StringComparer.Ordinal).ToList();
        var unique = new List<NewsCard>(); foreach (var card in ranked) if (!unique.Any(c => SharedPolicy.SameStory(c.Article.Title, card.Article.Title))) unique.Add(card);
        var fresh = unique.Where(c => now.ToUnixTimeSeconds() - c.Article.Published <= 172800).ToList();
        if (fresh.Count >= 3) unique = fresh;
        if (rotation >= unique.Count) rotation = 0;
        Cards = unique.Skip(rotation).Take(3).ToArray();
        if (cache.Fetched > 0 && !Busy) Status = "Cached on " + DateTimeOffset.FromUnixTimeSeconds((long)cache.Fetched).ToLocalTime().ToString("g") + (Preferences.Enabled ? " · matching stays on this PC" : " · news is off");
    }
    public NewsReadingSupport MakePopupReader() => new(Path.GetDirectoryName(preferencesPath)!)
    { Translate = Reader.Translate, CachedWordMeaning = Reader.CachedWordMeaning, KnowledgeLevel = Reader.KnowledgeLevel,
      Speak = Reader.Speak, SaveWord = Reader.SaveWord, BeforeHelp = Reader.BeforeHelp };
    public void ConfigurePopups(bool enabled, int interval)
    {
        var popup = PopupPreferences; bool allowed = enabled && Preferences.Enabled && Preferences.Background;
        if (allowed && (!popup.Enabled || popup.IntervalMinutes != interval)) popup.LastShown = clock().ToUnixTimeSeconds();
        popup.Enabled = allowed; popup.IntervalMinutes = new[] { 60, 120, 240 }.Contains(interval) ? interval : 120;
        if (allowed) Preferences.Notify = false; else CancelGeneration();
        Preferences.Popup = popup; popupRevision = Guid.NewGuid(); popupRetry = null;
        PopupStatus = allowed ? "Scheduled cards are on. The first card follows your chosen interval." : "Scheduled cards are off.";
        Save(); Changed?.Invoke();
    }
    public void PausePopupsForToday(bool paused)
    {
        var popup = PopupPreferences;
        popup.PausedUntil = paused ? new DateTimeOffset(clock().Date.AddDays(1), TimeZoneInfo.Local.GetUtcOffset(clock().Date.AddDays(1))).ToUnixTimeSeconds() : null;
        Preferences.Popup = popup; popupRevision = Guid.NewGuid(); CancelGeneration(); Save();
        PopupStatus = paused ? "News cards are paused for today." : "News cards resumed."; Changed?.Invoke();
    }
    private NewsArticle[] PopupCandidates => Cards.Select(c => c.Article).Where(a => !PopupPreferences.Ids.Contains(a.Id) && clock().ToUnixTimeSeconds() - a.Published is >= 0 and <= 172800).ToArray();
    public bool PopupDue()
    {
        var now = clock(); var popup = PopupPreferences;
        bool blocked = ReadingActive() || PageVisible || PopupVisible || PopupsPaused || !PopupAllowed() || popupRetry is { } retry && now < retry;
        return SharedPolicy.bp_news_popup_due(Preferences.Enabled ? 1 : 0, Preferences.Background ? 1 : 0, popup.Enabled ? 1 : 0, blocked ? 1 : 0,
            now.Hour, now.ToUnixTimeSeconds() - (popup.LastShown ?? now.ToUnixTimeSeconds()), popup.IntervalMinutes,
            popup.Day == now.ToString("yyyy-MM-dd") ? popup.Shown : 0, PopupCandidates.Length) != 0;
    }
    public async Task TickPopupAsync(bool preview = false)
    {
        bool Eligible() => preview ? Preferences.Enabled && !ReadingActive() && !PopupVisible && PopupAllowed() : PopupDue();
        if (disposed || popupPreparing || !Eligible() || (preview ? Cards.Select(c => c.Article) : PopupCandidates).FirstOrDefault() is not { } candidate || PresentPopup is null)
        { if (preview) { PopupStatus = "Pause screen reading, enable DR news, and refresh news before trying a card."; Changed?.Invoke(); } return; }
        if (!(ModelAvailable?.Invoke() ?? SimplifyExcerpt is not null)) { PopupStatus = "Install local AI in Settings to receive adapted news cards."; Changed?.Invoke(); return; }
        popupPreparing = true; var revision = popupRevision;
        try
        {
            await SimplifyAsync(candidate);
            if (disposed || popupRevision != revision || !Eligible()) return;
            if (Simplified(candidate) is not { } text || SimplifiedModel(candidate) is not { } model)
            { PopupStatus = "Adapted card unavailable. Will try again later; the original remains in Word Book."; popupRetry = clock().AddMinutes(10); Changed?.Invoke(); return; }
            if (PresentPopup(new(candidate, text, model, preview)))
            {
                var popup = PopupPreferences; var now = clock(); string day = now.ToString("yyyy-MM-dd");
                popup.Shown = (popup.Day == day ? popup.Shown : 0) + 1; popup.Day = day; popup.LastShown = now.ToUnixTimeSeconds();
                popup.Ids = popup.Ids.Append(candidate.Id).TakeLast(100).ToArray(); Preferences.Popup = popup;
                PopupStatus = "A short Danish news card was shown."; Save(); Changed?.Invoke();
            }
        }
        finally { popupPreparing = false; }
    }
    public bool DigestDue(bool reading, bool permitted)
    {
        var now = clock(); bool quiet = now.Hour < 9 || now.Hour >= 21 || now.Hour != Preferences.DigestHour;
        return SharedPolicy.bp_digest(Preferences.Enabled ? 1 : 0, Preferences.Background ? 1 : 0, Preferences.Notify ? 1 : 0, permitted ? 1 : 0, reading || PageVisible ? 1 : 0, quiet ? 1 : 0, Preferences.LastDigestDay == now.ToString("yyyy-MM-dd") ? 1 : 0, DigestCandidates.Count) != 0;
    }
    public IReadOnlyList<NewsArticle> DigestCandidates => Cards.Where(c => !Preferences.LastDigestIds.Contains(c.Article.Id) && clock().ToUnixTimeSeconds() - c.Article.Published is >= 0 and <= 604800).Select(c => c.Article).ToArray();
    public void DigestSent() { Preferences.LastDigestDay = clock().ToString("yyyy-MM-dd"); Preferences.LastDigestIds = Preferences.LastDigestIds.Concat(DigestCandidates.Take(1).Select(a => a.Id)).Distinct().TakeLast(100).ToArray(); Save(); }
    public void Dispose() { disposed = true; fetch?.Cancel(); CancelGeneration(); Reader.Dispose(); http?.Dispose(); }
}
