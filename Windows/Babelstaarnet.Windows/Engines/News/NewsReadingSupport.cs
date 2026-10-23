using Babelstaarnet.Core;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace Babelstaarnet.Windows;
internal sealed record NewsEnglish(string[] Parts, double Created);
internal sealed record NewsGloss(string Text, double Created);
internal sealed record NewsWordHelp(string ArticleKey, string Word, string Context, string Meaning, string Status, bool Saved = false);
internal sealed class NewsReadingCache
{
    public Dictionary<string, NewsEnglish> English { get; set; } = [];
    public Dictionary<string, NewsGloss>? Words { get; set; } = [];
}
// Receives public source text and local adapters; never requests a URL or captures a screen.
internal sealed class NewsReadingSupport : IDisposable
{
    private static readonly JsonSerializerOptions Json = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
    private readonly string path;
    private readonly Dictionary<string, NewsEnglish> meanings = [];
    private readonly Dictionary<string, string> states = [];
    private readonly Dictionary<string, Task> tasks = [];
    private readonly Dictionary<string, Guid> owners = [];
    private bool disposed;
    private readonly HashSet<string> revealed = [];
    private CancellationTokenSource lifetime = new();
    private CancellationTokenSource? wordRequest;
    private readonly Dictionary<string, NewsGloss> wordMeanings = [];
    private readonly Dictionary<string, Dictionary<string, string>> glossPlans = [];
    private readonly Dictionary<string, string> wordStates = [];
    public Func<string, int> KnowledgeLevel { get; set; } = _ => 0;
    public NewsWordHelp? Selected { get; private set; }
    public Func<IReadOnlyList<string>, CancellationToken, Task<IReadOnlyList<string>>>? Translate { get; set; }
    public Func<string, string?> CachedWordMeaning { get; set; } = _ => null;
    public Action? BeforeHelp { get; set; }
    public Action<string>? Speak { get; set; }
    public Action<string, string, string>? SaveWord { get; set; }
    public event Action? Changed;
    public NewsReadingSupport(string directory)
    {
        path = Path.Combine(directory, "news-reading.json");
        try
        {
            if (File.Exists(path) && new FileInfo(path).Length <= 2_000_000 && JsonSerializer.Deserialize<NewsReadingCache>(File.ReadAllText(path), Json) is { } cache)
            {
                foreach (var p in (cache.Words ?? []).Where(p => p.Key.Length <= 100 && p.Value is not null && double.IsFinite(p.Value.Created) && !string.IsNullOrEmpty(p.Value.Text) && p.Value.Text.Length <= 160).OrderByDescending(p => p.Value.Created).Take(1024)) wordMeanings[p.Key] = p.Value;
                foreach (var p in (cache.English ?? []).Where(p => p.Key.Length < 1000 && p.Value is not null && double.IsFinite(p.Value.Created) && p.Value.Parts is { Length: >= 1 and <= 2 } && p.Value.Parts.All(s => !string.IsNullOrWhiteSpace(s) && s.Length <= 18000)).OrderByDescending(p => p.Value.Created).Take(32)) meanings[p.Key] = p.Value;
            }
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException) { }
    }
    public static string[] SourceParts(NewsArticle article) => article.Summary.Length == 0 ? [article.Title] : [article.Title, article.Summary];
    public static string Key(NewsArticle article) => article.Id + ":da-en-v1:" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(string.Join('\u001f', SourceParts(article)))));
    public NewsEnglish? Meaning(NewsArticle article) => meanings.TryGetValue(Key(article), out var value) && value.Parts.Length == SourceParts(article).Length ? value : null;
    public string? State(NewsArticle article) => states.GetValueOrDefault(Key(article));
    public bool IsVisible(NewsArticle article) => revealed.Contains(Key(article));
    public void HideTranslation(NewsArticle article) { revealed.Remove(Key(article)); Changed?.Invoke(); }
    public string? WordState(NewsArticle article) => wordStates.GetValueOrDefault(Key(article));
    private static string Normalized(string word) => word.Normalize().ToLowerInvariant();
    private string? WordMeaning(string word) => CachedWordMeaning(word) ?? wordMeanings.GetValueOrDefault(Normalized(word))?.Text;
    public string? Gloss(string word, NewsArticle article)
    {
        string key = Key(article), unit = Normalized(word);
        string? text = glossPlans.TryGetValue(key, out var plan) ? plan.GetValueOrDefault(unit) : SharedPolicy.bp_news_gloss(KnowledgeLevel(word), 1, 1) != 0 ? WordMeaning(word) : null;
        return !string.IsNullOrWhiteSpace(text) && text.Length <= 160 && Normalized(text) != unit && Pieces(text).Length <= 10 ? text : null;
    }
    public async Task PrepareAsync(NewsArticle article, bool requested = false)
    {
        if (disposed) return;
        if (!requested) { await PrepareWordsAsync(article); return; }
        string key = Key(article);
        BeforeHelp?.Invoke(); revealed.Add(key); Changed?.Invoke();
        int decision = SharedPolicy.bp_reading_help(1, 0, Meaning(article) is not null ? 1 : 0, Translate is not null ? 1 : 0);
        if (decision <= 1) return;
        if (decision == 3) { states[key] = "Set up local translation in Settings for sentence help."; Changed?.Invoke(); return; }
        await PerformAsync(key, async (owner, token) =>
        {
            states[key] = "Preparing sentence help on this device…"; Changed?.Invoke();
            try
            {
                string[] source = SourceParts(article); var result = await Translate!(source, token); token.ThrowIfCancellationRequested();
                if (result.Count != source.Length || result.Any(s => string.IsNullOrWhiteSpace(s) || s.Length > 18000)) throw new InvalidDataException("Incomplete local translation.");
                if (owners.GetValueOrDefault(key) != owner) return;
                meanings[key] = new(result.ToArray(), DateTimeOffset.Now.ToUnixTimeSeconds());
                if (meanings.Count > 32) meanings.Remove(meanings.Where(p => p.Key != key).MinBy(p => p.Value.Created).Key);
                states.Remove(key); Persist();
            }
            catch (OperationCanceledException) { if (owners.GetValueOrDefault(key) == owner) states.Remove(key); }
            catch (Exception e) { if (owners.GetValueOrDefault(key) == owner) states[key] = "Sentence help unavailable. Try again or select a word. " + e.Message; }
        });
    }
    private async Task PrepareWordsAsync(NewsArticle article)
    {
        string key = Key(article), operation = "words:" + key;
        if (!glossPlans.TryGetValue(key, out var plan))
        {
            plan = []; glossPlans[key] = plan;
            foreach (string word in SourceParts(article).SelectMany(Pieces).Select(Word).OfType<string>())
                if (SharedPolicy.bp_news_gloss(KnowledgeLevel(word), 1, 1) != 0) plan[Normalized(word)] = WordMeaning(word) ?? "";
            Changed?.Invoke();
        }
        var missing = plan.Where(p => p.Value.Length == 0).Select(p => p.Key).Order(StringComparer.Ordinal).Take(64).ToArray();
        if (missing.Length == 0) { wordStates.Remove(key); return; }
        if (Translate is null) { wordStates[key] = "Word help needs local translation in Settings. Select a word for available dictionary help."; Changed?.Invoke(); return; }
        await PerformAsync(operation, async (owner, token) =>
        {
            wordStates[key] = "Adding small word hints on this device…"; Changed?.Invoke();
            try
            {
                var result = await Translate(missing, token); token.ThrowIfCancellationRequested();
                if (result.Count != missing.Length || result.Any(s => string.IsNullOrWhiteSpace(s) || s.Length > 18000)) throw new InvalidDataException("Incomplete word meanings.");
                if (owners.GetValueOrDefault(operation) != owner) return;
                for (int i = 0; i < missing.Length; i++)
                {
                    string gloss = result[i].Trim(); plan[missing[i]] = gloss;
                    if (gloss.Length <= 160) wordMeanings[missing[i]] = new(gloss, DateTimeOffset.Now.ToUnixTimeSeconds());
                }
                foreach (var old in wordMeanings.OrderByDescending(p => p.Value.Created).Skip(1024).ToArray()) wordMeanings.Remove(old.Key);
                wordStates.Remove(key); Persist();
            }
            catch (OperationCanceledException) { if (owners.GetValueOrDefault(operation) == owner) wordStates.Remove(key); }
            catch { if (owners.GetValueOrDefault(operation) == owner) wordStates[key] = "Some word hints are unavailable. Select a word or use sentence help."; }
        });
    }
    private async Task PerformAsync(string key, Func<Guid, CancellationToken, Task> work)
    {
        if (tasks.TryGetValue(key, out var running)) { await running; return; }
        var token = lifetime.Token; var owner = Guid.NewGuid(); owners[key] = owner;
        var completion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously); tasks[key] = completion.Task;
        try { await work(owner, token); }
        finally { if (owners.GetValueOrDefault(key) == owner) { tasks.Remove(key); owners.Remove(key); } completion.TrySetResult(); if (!disposed) Changed?.Invoke(); }
    }
    public async Task LookupAsync(string word, NewsArticle article, string? context = null)
    {
        if (disposed) return;
        BeforeHelp?.Invoke(); wordRequest?.Cancel(); using var request = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token); wordRequest = request;
        string? cached = WordMeaning(word);
        Selected = new(Key(article), word, context ?? string.Join(' ', SourceParts(article)), cached ?? "", cached is null ? "Looking up on this device…" : "Word meaning · check against the Danish context"); Changed?.Invoke();
        if (cached is not null) { wordRequest = null; return; }
        if (Translate is null) { Selected = Selected with { Status = "Set up local translation in Settings for word meanings." }; Changed?.Invoke(); wordRequest = null; return; }
        try
        {
            var result = await Translate([word], request.Token); request.Token.ThrowIfCancellationRequested();
            if (ReferenceEquals(wordRequest, request)) Selected = new(Key(article), word, context ?? string.Join(' ', SourceParts(article)), result.FirstOrDefault() ?? "", "Word meaning · check against the Danish context");
        }
        catch (OperationCanceledException) { }
        catch { if (ReferenceEquals(wordRequest, request)) Selected = Selected! with { Status = "Word meaning unavailable. Sentence help is also available." }; }
        finally { if (ReferenceEquals(wordRequest, request)) wordRequest = null; Changed?.Invoke(); }
    }
    public void SaveSelection(NewsArticle article)
    {
        if (Selected is { } value && value.ArticleKey == Key(article) && value.Meaning.Length > 0 && SaveWord is not null)
        { SaveWord(value.Word, value.Meaning, value.Context); Selected = value with { Saved = true }; Changed?.Invoke(); }
    }
    public void Cancel() { if (disposed) return; lifetime.Cancel(); lifetime.Dispose(); lifetime = new(); tasks.Clear(); owners.Clear(); states.Clear(); wordStates.Clear(); glossPlans.Clear(); revealed.Clear(); wordRequest?.Cancel(); wordRequest = null; Selected = null; }
    public void Dispose() { if (disposed) return; Cancel(); disposed = true; lifetime.Dispose(); }
    private void Persist()
    {
        try { Directory.CreateDirectory(Path.GetDirectoryName(path)!); string temp = path + ".tmp"; File.WriteAllText(temp, JsonSerializer.Serialize(new NewsReadingCache { English = meanings, Words = wordMeanings }, Json)); File.Move(temp, path, true); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
    }
    public static string[] Pieces(string text) => text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
    public static string? Word(string piece) { var match = ReadingPolicy.Words().Match(piece); return match.Success ? match.Value : null; }
}
