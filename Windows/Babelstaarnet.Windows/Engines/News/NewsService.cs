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
internal sealed class NewsPreferences
{
    public bool Enabled { get; set; }
    public bool Background { get; set; }
    public bool Notify { get; set; }
    public int Topic { get; set; }
    public int DigestHour { get; set; } = 18;
    public string? LastDigestDay { get; set; }
}
internal sealed class NewsCache
{
    public double Fetched { get; set; }
    public int Topic { get; set; }
    public NewsArticle[] Articles { get; set; } = [];
    public Dictionary<string, double> Seen { get; set; } = [];
    public Dictionary<string, double> SeenTitles { get; set; } = [];
}

// DR metadata only. No browser engine, remote assets, personalized request or cloud fallback.
// Source guide: https://www.dr.dk/nyheder/dr-nyheder-som-rss-feed (verified 2026-10-22).
internal sealed class NewsService : IDisposable
{
    public static readonly string[] Topics = ["Latest", "Denmark", "World", "Money", "Politics", "Science", "Culture", "Sport"];
    public const string Disclosure = "Connects to DR to fetch public news. Matching stays on this PC. No word list, screenshots or learning records are uploaded. DR receives ordinary requests, including your IP address and requested URLs. Opening an original uses your browser.";
    private static readonly JsonSerializerOptions Json = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
    private readonly string preferencesPath, cachePath;
    private readonly Func<Uri, CancellationToken, Task<string>> download;
    private readonly Func<DateTimeOffset> clock;
    private readonly HttpClient? http;
    private CancellationTokenSource? fetch;
    private DateTimeOffset? lastAttempt;
    private NewsCache cache;
    private bool disposed;
    private int rotation;
    public NewsPreferences Preferences { get; }
    public bool Busy { get; private set; }
    public string Status { get; private set; } = "News is optional. Enable it to connect to DR.";
    public IReadOnlyList<NewsCard> Cards { get; private set; } = [];
    public event Action? Changed;
    public Func<IEnumerable<string>> LearningUnits { get; set; } = () => [];
    public NewsService(string directory, Func<Uri, CancellationToken, Task<string>>? download = null, Func<DateTimeOffset>? clock = null)
    {
        this.clock = clock ?? (() => DateTimeOffset.Now);
        preferencesPath = Path.Combine(directory, "news-preferences.json"); cachePath = Path.Combine(directory, "news-cache.json");
        Preferences = Load<NewsPreferences>(preferencesPath) ?? new(); cache = Load<NewsCache>(cachePath) ?? new();
        Preferences.Topic = Math.Clamp(Preferences.Topic, 0, Topics.Length - 1); Preferences.DigestHour = Math.Clamp(Preferences.DigestHour, 9, 20);
        if (!Preferences.Enabled) Preferences.Background = Preferences.Notify = false;
        if (!Preferences.Background) Preferences.Notify = false;
        cache.Articles ??= []; cache.Seen ??= []; cache.SeenTitles ??= [];
        cache.Articles = cache.Articles.Where(ValidArticle).Take(256).ToArray();
        if (!double.IsFinite(cache.Fetched) || cache.Fetched < 0 || cache.Fetched > this.clock().ToUnixTimeSeconds() + 3600) cache.Fetched = 0;
        if (download is null)
        {
            http = new(new SocketsHttpHandler { AllowAutoRedirect = false, UseCookies = false }) { Timeout = TimeSpan.FromSeconds(15) };
            http.DefaultRequestHeaders.UserAgent.ParseAdd("Babelstaarnet/0.5.1");
            this.download = DownloadAsync;
        }
        else this.download = download;
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
        if (!enabled || changedTopic) { fetch?.Cancel(); rotation = 0; }
        if (!enabled) { Preferences.Background = Preferences.Notify = false; Status = "News is off. Cached articles remain available offline."; }
        Save(); SelectCards(); Changed?.Invoke();
    }
    public async Task RefreshAsync(bool manual = false, bool background = false)
    {
        if (disposed || Busy) return;
        var now = clock();
        double successAge = cache.Topic == Preferences.Topic && cache.Fetched > 0 ? now.ToUnixTimeSeconds() - cache.Fetched : -1;
        if (SharedPolicy.bp_fetch(Preferences.Enabled ? 1 : 0, Preferences.Background ? 1 : 0, background ? 1 : 0, manual ? 1 : 0,
            lastAttempt is { } attempted ? (now - attempted).TotalSeconds : -1, successAge) == 0) return;
        lastAttempt = now; Busy = true; Status = "Fetching public headlines from DR…"; Changed?.Invoke();
        using var request = new CancellationTokenSource(); fetch = request; int topic = Preferences.Topic;
        try
        {
            string xml = await download(new(SharedPolicy.FeedUrl(topic)), request.Token);
            request.Token.ThrowIfCancellationRequested(); if (!Preferences.Enabled || topic != Preferences.Topic || disposed) return;
            var articles = ParseFeed(xml, topic);
            if (articles.Length == 0) throw new InvalidDataException("DR returned no usable news entries.");
            cache.Articles = articles; cache.Topic = topic; cache.Fetched = now.ToUnixTimeSeconds(); rotation = 0;
            Status = "Updated from DR · " + now.ToString("g"); Save(); SelectCards();
        }
        catch (OperationCanceledException) when (request.IsCancellationRequested) { }
        catch (Exception e) when (e is HttpRequestException or IOException or XmlException or TaskCanceledException or InvalidOperationException)
        { Status = "News could not be updated. Cached content is available. " + e.Message; }
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
    public void NextGroup() { rotation += 3; SelectCards(); Changed?.Invoke(); }
    public void MarkSeen(NewsArticle article)
    {
        cache.Seen[article.Id] = clock().ToUnixTimeSeconds(); cache.SeenTitles[article.Title] = clock().ToUnixTimeSeconds();
        cache.SeenTitles = cache.SeenTitles.Where(p => clock().ToUnixTimeSeconds() - p.Value <= 604800).TakeLast(100).ToDictionary(p => p.Key, p => p.Value);
        cache.Seen = cache.Seen.Where(p => clock().ToUnixTimeSeconds() - p.Value <= 604800).TakeLast(256).ToDictionary(p => p.Key, p => p.Value);
        Save(); SelectCards(); Changed?.Invoke();
    }
    public void SelectCards()
    {
        var now = clock(); var units = LearningUnits().Where(s => !ReadingPolicy.StructuralWords.Contains(ReadingPolicy.Key(s))).Distinct().Take(200).ToArray();
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
    public bool DigestDue(bool reading, bool permitted)
    {
        var now = clock(); bool quiet = now.Hour < 9 || now.Hour >= 21 || now.Hour != Preferences.DigestHour;
        return SharedPolicy.bp_digest(Preferences.Enabled ? 1 : 0, Preferences.Background ? 1 : 0, Preferences.Notify ? 1 : 0, permitted ? 1 : 0, reading ? 1 : 0, quiet ? 1 : 0, Preferences.LastDigestDay == now.ToString("yyyy-MM-dd") ? 1 : 0, Cards.Count) != 0;
    }
    public void DigestSent() { Preferences.LastDigestDay = clock().ToString("yyyy-MM-dd"); Save(); }
    public void Dispose() { disposed = true; fetch?.Cancel(); http?.Dispose(); }
}
