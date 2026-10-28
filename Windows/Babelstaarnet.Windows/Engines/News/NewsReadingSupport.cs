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
internal sealed record NewsWordPresentation(string Text, int Mode); // 0 familiar, 1 English, 2 new Danish, 3 missing help
internal sealed class NewsReadingCache
{
    public Dictionary<string, NewsEnglish> English { get; set; } = [];
    public Dictionary<string, NewsGloss>? Words { get; set; } = [];
    public Dictionary<string, Dictionary<string, string>>? Contextual { get; set; } = [];
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
    private readonly Dictionary<string, Dictionary<string, string>> contextual = [];
    private readonly Dictionary<string, HashSet<string>> learningPlans = [];
    private readonly Dictionary<string, Dictionary<string, int>> levelPlans = [];
    private readonly Dictionary<string, int> readerBands = [];
    private readonly Dictionary<string, string> wordStates = [];
    public Func<string, int> KnowledgeLevel { get; set; } = _ => 0;
    public Func<bool> SupportedReading { get; set; } = () => false;
    public IReadOnlyDictionary<string, int> WordBands { get; set; } = new Dictionary<string, int>();
    public Func<string, IReadOnlyList<string>, CancellationToken, Task<IReadOnlyDictionary<string, string>>>? ContextualWords { get; set; }
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
                foreach (var p in (cache.Contextual ?? []).Where(p => p.Key.Length < 1000 && p.Value is { Count: <= 256 }).TakeLast(32))
                    contextual[p.Key] = p.Value.Where(v => v.Key.Length <= 100 && Usable(v.Value)).ToDictionary();
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
        return !learningPlans.GetValueOrDefault(key, []).Contains(unit) && Usable(text) && Normalized(text!) != unit ? text : null;
    }
    private static bool Usable(string? text) => !string.IsNullOrWhiteSpace(text) && text.Length <= 160 && Pieces(text).Length <= 10;
    public bool Ready(NewsArticle article) => glossPlans.TryGetValue(Key(article), out var plan) && plan.Values.All(Usable);
    public NewsWordPresentation Presentation(string piece, NewsArticle article)
    {
        string? word = Word(piece); if (word is null) return new(piece, 0);
        string key = Key(article), unit = Normalized(word);
        if (!glossPlans.TryGetValue(key, out var plan)) return KnowledgeLevel(word) >= 4 ? new(piece, 0) : new("…", 3);
        if (!plan.TryGetValue(unit, out var meaning)) return new(piece, 0);
        if (!learningPlans.ContainsKey(key)) return new("…", 3);
        if (!Usable(meaning)) return new(piece, 3);
        if (learningPlans.GetValueOrDefault(key, []).Contains(unit)) return new(piece, 2);
        if (Normalized(meaning) == unit) return new(piece, 0);
        var match = ReadingPolicy.Words().Match(piece);
        return new(piece[..match.Index] + meaning + piece[(match.Index + match.Length)..], 1);
    }
    private void FinishPlan(NewsArticle article)
    {
        string key = Key(article); if (learningPlans.ContainsKey(key)) return;
        var targets = new HashSet<string>(); var plan = glossPlans[key];
        int budget = SupportedReading() ? 0 : SharedPolicy.bp_news_target_budget(SourceParts(article).SelectMany(Pieces).Count(p => Word(p) is not null));
        var words = SourceParts(article).SelectMany(Pieces).Select(Word).OfType<string>().Select(Normalized).Distinct().ToArray();
        foreach (string word in words.Where(plan.ContainsKey).OrderByDescending(w => levelPlans[key][w]).ThenBy(w => WordBands.GetValueOrDefault(w, int.MaxValue)))
            if (SharedPolicy.bp_news_word_mode(levelPlans[key][word], WordBands.GetValueOrDefault(word), readerBands[key], Usable(plan[word]) && Normalized(plan[word]) != word ? 1 : 0, targets.Count, budget) == 2) targets.Add(word);
        learningPlans[key] = targets;
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
        var forms = SourceParts(article).SelectMany(Pieces).Select(Word).OfType<string>().DistinctBy(Normalized).ToDictionary(Normalized);
        if (!glossPlans.TryGetValue(key, out var plan))
        {
            plan = []; glossPlans[key] = plan; var levels = levelPlans[key] = [];
            foreach (var (unit, word) in forms)
                if (KnowledgeLevel(word) < 4) { levels[unit] = KnowledgeLevel(word); plan[unit] = contextual.GetValueOrDefault(key)?.GetValueOrDefault(unit) ?? WordMeaning(word) ?? ""; }
            int Total(int band) => WordBands.Count(p => p.Value == band);
            int Known(int band) => WordBands.Count(p => p.Value == band && KnowledgeLevel(p.Key) >= 4);
            readerBands[key] = SharedPolicy.bp_news_reader_band(Known(1), Total(1), Known(2), Total(2));
        }
        if (Ready(article) && (learningPlans.ContainsKey(key) || ContextualWords is null || contextual.GetValueOrDefault(key) is { } remembered && plan.Keys.All(remembered.ContainsKey)))
        { FinishPlan(article); wordStates.Remove(key); Changed?.Invoke(); return; }
        await PerformAsync(operation, async (owner, token) =>
        {
            wordStates[key] = "Preparing English support on this device…"; Changed?.Invoke();
            void Accept(string word, string? value, bool inContext)
            {
                if (!Usable(value) || !plan.ContainsKey(word)) return;
                plan[word] = value!.Trim(); wordMeanings[word] = new(plan[word], DateTimeOffset.Now.ToUnixTimeSeconds());
                if (inContext) { if (!contextual.ContainsKey(key)) contextual[key] = []; contextual[key][word] = plan[word]; }
            }
            try
            {
                if (ContextualWords is not null)
                    foreach (string part in SourceParts(article))
                    foreach (var pieces in Pieces(part).Chunk(32))
                    {
                        var words = pieces.Select(Word).OfType<string>().DistinctBy(Normalized)
                            .Where(w => plan.ContainsKey(Normalized(w)) && contextual.GetValueOrDefault(key)?.ContainsKey(Normalized(w)) != true).ToArray();
                        if (words.Length == 0) continue;
                        try
                        {
                            var result = await ContextualWords(string.Join(' ', pieces), words, token); token.ThrowIfCancellationRequested();
                            if (owners.GetValueOrDefault(operation) != owner) return;
                            foreach (var item in result) Accept(Normalized(item.Key), item.Value, true);
                        }
                        catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
                        catch { /* Keep available help and try the ordinary offline adapter. */ }
                    }
                if (Translate is not null)
                    foreach (var batch in plan.Where(p => !Usable(p.Value)).Select(p => p.Key).Take(256).ToArray().Chunk(8))
                    {
                        try
                        {
                            var result = await Translate(batch.Select(w => forms[w]).ToArray(), token); token.ThrowIfCancellationRequested();
                            if (result.Count != batch.Length) throw new InvalidDataException("Incomplete word batch.");
                            if (owners.GetValueOrDefault(operation) != owner) return;
                            // One empty result must never discard the rest of a card's support.
                            for (int i = 0; i < batch.Length; i++) Accept(batch[i], result[i], false);
                        }
                        catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
                        catch { /* Other batches can still succeed. */ }
                    }
                if (owners.GetValueOrDefault(operation) != owner) return;
                FinishPlan(article);
                if (Ready(article)) wordStates.Remove(key);
                else wordStates[key] = "Some English support is unavailable. Select a word for help, or retry.";
                foreach (var old in wordMeanings.OrderByDescending(p => p.Value.Created).Skip(1024).ToArray()) wordMeanings.Remove(old.Key);
                foreach (var old in contextual.Keys.Where(k => k != key).Take(Math.Max(0, contextual.Count - 32)).ToArray()) contextual.Remove(old);
                Persist();
            }
            catch (OperationCanceledException) { if (owners.GetValueOrDefault(operation) == owner) wordStates.Remove(key); }
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
        string? cached = glossPlans.GetValueOrDefault(Key(article))?.GetValueOrDefault(Normalized(word));
        if (!Usable(cached)) cached = WordMeaning(word);
        if (!Usable(cached)) cached = null;
        learningPlans.GetValueOrDefault(Key(article))?.Remove(Normalized(word));
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
    public void Cancel() { if (disposed) return; lifetime.Cancel(); lifetime.Dispose(); lifetime = new(); tasks.Clear(); owners.Clear(); states.Clear(); wordStates.Clear(); glossPlans.Clear(); learningPlans.Clear(); levelPlans.Clear(); readerBands.Clear(); revealed.Clear(); wordRequest?.Cancel(); wordRequest = null; Selected = null; }
    public void Dispose() { if (disposed) return; Cancel(); disposed = true; lifetime.Dispose(); }
    private void Persist()
    {
        try { Directory.CreateDirectory(Path.GetDirectoryName(path)!); string temp = path + ".tmp"; File.WriteAllText(temp, JsonSerializer.Serialize(new NewsReadingCache { English = meanings, Words = wordMeanings, Contextual = contextual }, Json)); File.Move(temp, path, true); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
    }
    public static string[] Pieces(string text) => text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
    public static string? Word(string piece) { var match = ReadingPolicy.Words().Match(piece); return match.Success ? match.Value : null; }
}
