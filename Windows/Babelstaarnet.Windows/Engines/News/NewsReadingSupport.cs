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
internal sealed record NewsWordHelp(string ArticleKey, string Word, string Meaning, string Status, bool Saved = false);
internal sealed class NewsReadingCache
{
    public Dictionary<string, NewsEnglish> English { get; set; } = [];
    public bool? ShowEnglish { get; set; } = true;
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
    public bool ShowEnglish { get; private set; } = true;
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
                ShowEnglish = cache.ShowEnglish ?? true;
                foreach (var p in (cache.English ?? []).Where(p => p.Key.Length < 1000 && p.Value is not null && double.IsFinite(p.Value.Created) && p.Value.Parts is { Length: >= 1 and <= 2 } && p.Value.Parts.All(s => !string.IsNullOrWhiteSpace(s) && s.Length <= 18000)).OrderByDescending(p => p.Value.Created).Take(32)) meanings[p.Key] = p.Value;
            }
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException) { }
    }
    public static string[] SourceParts(NewsArticle article) => article.Summary.Length == 0 ? [article.Title] : [article.Title, article.Summary];
    public static string Key(NewsArticle article) => article.Id + ":da-en-v1:" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(string.Join('\u001f', SourceParts(article)))));
    public NewsEnglish? Meaning(NewsArticle article) => meanings.TryGetValue(Key(article), out var value) && value.Parts.Length == SourceParts(article).Length ? value : null;
    public string? State(NewsArticle article) => states.GetValueOrDefault(Key(article));
    public bool IsVisible(NewsArticle article) => ShowEnglish || revealed.Contains(Key(article));
    public void SetEnglish(bool enabled) { ShowEnglish = enabled; revealed.Clear(); if (!enabled) Cancel(); Persist(); Changed?.Invoke(); }
    public async Task PrepareAsync(NewsArticle article, bool requested = false)
    {
        if (disposed) return;
        string key = Key(article);
        if (requested) { BeforeHelp?.Invoke(); revealed.Add(key); }
        int decision = SharedPolicy.bp_reading_help(requested ? 1 : 0, ShowEnglish ? 1 : 0, Meaning(article) is not null ? 1 : 0, Translate is not null ? 1 : 0);
        if (decision <= 1) { Changed?.Invoke(); return; }
        if (decision == 3) { states[key] = "Set up local translation in Settings to read this with English support."; Changed?.Invoke(); return; }
        if (tasks.TryGetValue(key, out var running)) { await running; return; }
        var token = lifetime.Token; var owner = Guid.NewGuid(); owners[key] = owner;
        var completion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        tasks[key] = completion.Task;
        async Task Work()
        {
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
            catch (Exception e) { if (owners.GetValueOrDefault(key) == owner) states[key] = "English support is unavailable. Check local translation in Settings, then try again. " + e.Message; }
            finally { if (owners.GetValueOrDefault(key) == owner) { tasks.Remove(key); owners.Remove(key); } completion.TrySetResult(); if (!disposed) Changed?.Invoke(); }
        }
        states[key] = "Preparing English on this device…";
        Changed?.Invoke(); await Work();
    }
    public async Task LookupAsync(string word, NewsArticle article)
    {
        if (disposed) return;
        BeforeHelp?.Invoke(); wordRequest?.Cancel(); using var request = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token); wordRequest = request;
        string? cached = CachedWordMeaning(word);
        Selected = new(Key(article), word, cached ?? "", cached is null ? "Looking up on this device…" : "Word meaning · use the English sentence for context"); Changed?.Invoke();
        if (cached is not null) { wordRequest = null; return; }
        if (Translate is null) { Selected = Selected with { Status = "Set up local translation in Settings for word meanings." }; Changed?.Invoke(); wordRequest = null; return; }
        try
        {
            var result = await Translate([word], request.Token); request.Token.ThrowIfCancellationRequested();
            if (ReferenceEquals(wordRequest, request)) Selected = new(Key(article), word, result.FirstOrDefault() ?? "", "Word meaning · use the English sentence for context");
        }
        catch (OperationCanceledException) { }
        catch { if (ReferenceEquals(wordRequest, request)) Selected = Selected! with { Status = "Word meaning unavailable. The English sentence above can help." }; }
        finally { if (ReferenceEquals(wordRequest, request)) wordRequest = null; Changed?.Invoke(); }
    }
    public void SaveSelection(NewsArticle article)
    {
        if (Selected is { } value && value.ArticleKey == Key(article) && value.Meaning.Length > 0 && SaveWord is not null)
        { SaveWord(value.Word, value.Meaning, string.Join(' ', SourceParts(article))); Selected = value with { Saved = true }; Changed?.Invoke(); }
    }
    public void Cancel() { if (disposed) return; lifetime.Cancel(); lifetime.Dispose(); lifetime = new(); tasks.Clear(); owners.Clear(); states.Clear(); wordRequest?.Cancel(); wordRequest = null; Selected = null; }
    public void Dispose() { if (disposed) return; Cancel(); disposed = true; lifetime.Dispose(); }
    private void Persist()
    {
        try { Directory.CreateDirectory(Path.GetDirectoryName(path)!); string temp = path + ".tmp"; File.WriteAllText(temp, JsonSerializer.Serialize(new NewsReadingCache { English = meanings, ShowEnglish = ShowEnglish }, Json)); File.Move(temp, path, true); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
    }
    public static string[] Pieces(string text) => text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
    public static string? Word(string piece) { var match = ReadingPolicy.Words().Match(piece); return match.Success ? match.Value : null; }
}
