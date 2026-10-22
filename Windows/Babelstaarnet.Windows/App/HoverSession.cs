using Babelstaarnet.Core;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace Babelstaarnet.Windows;

// Focus and speech appear independently of cold translation/context loading.
// Optional sentence work is bounded so stale text cannot monopolize the pipe.
internal sealed class HoverSession : IDisposable
{
    private readonly Func<string, string?> cached;
    private readonly Func<IReadOnlyList<string>, CancellationToken, Task<IReadOnlyList<string>>> translate;
    private readonly Func<string, bool> known;
    private CancellationTokenSource? pending;
    private CancellationTokenSource? sentenceRequest;
    private Dictionary<string, string> glosses = [];
    private readonly HashSet<string> contextualKeys = [];
    private readonly HashSet<string> visibleAnchors = [];
    private readonly HashSet<string> newSenseKeys = [];
    private readonly HashSet<string> learningTargets = [];
    private readonly HashSet<string> cooledUnits = [];
    public Func<string, string?>? PreviousMeaning { get; set; }
    public bool NewSense => Current is { } hit && newSenseKeys.Contains(ReadingPolicy.Key(hit.Word.Text));
    private readonly Dictionary<string, DateTimeOffset[]> helpHistory = [];
    private IReadOnlyList<BridgeToken>? projectedTokens, projectedExplanation;
    public HoveredText? Current { get; private set; }
    public string Meaning { get; private set; } = "";
    public string Explanation { get; private set; } = "";
    public string SentenceMeaning { get; private set; } = "";
    public bool SentenceHelp { get; private set; }
    public bool SupportedReading { get; set; }
    public Func<string, bool>? LearnedBefore { get; set; }
    public bool Loading => Current is not null && Meaning.Length == 0;
    public string Bridge => string.Join(' ', Tokens.Select(t => t.Text));
    public IReadOnlyList<BridgeToken> Tokens
    {
        get
        {
            if (projectedTokens is not null) return projectedTokens;
            if (Current is null) return projectedTokens = [];
            projectedTokens = BridgePresentation.Tokens(Current, glosses, known, KnowledgeLevel, SupportedReading, LearnedBefore,
                key => cooledUnits.Contains(key) || cooledUnits.Count >= 256 ? 2 : helpHistory.GetValueOrDefault(key, []).Count(at => DateTimeOffset.Now - at < TimeSpan.FromMinutes(10)), key => visibleAnchors.Contains(key) || newSenseKeys.Contains(key),
                key => !newSenseKeys.Contains(key) && SharedPolicy.bp_target_allowed(learningTargets.Count, learningTargets.Contains(key) ? 1 : 0) != 0, key => learningTargets.Add(key),
                key => PreviousMeaning?.Invoke(key) is { Length: > 0 } prior && ReadingPolicy.TryGloss(glosses, key, out var answer) && ReadingPolicy.Key(prior) == ReadingPolicy.Key(answer) && ReadingPolicy.Key(answer) != key);
            var words = ReadingPolicy.Words().Matches(Current.Line.Text);
            for (int i = 0; i < Math.Min(words.Count, projectedTokens.Count); i++) if (projectedTokens[i].English) visibleAnchors.Add(ReadingPolicy.Key(words[i].Value));
            return projectedTokens;
        }
    }
    public IReadOnlyList<BridgeToken> ExplanationTokens
    {
        get
        {
            if (projectedExplanation is not null) return projectedExplanation;
            if (Explanation.Length == 0) return projectedExplanation = [];
            var answers = new Dictionary<string, string>();
            foreach (System.Text.RegularExpressions.Match match in ReadingPolicy.Words().Matches(Explanation))
                if (ReadingPolicy.TryGloss(ReadingPolicy.Glosses, match.Value, out var local)) answers[ReadingPolicy.Key(match.Value)] = local;
                else if (cached(match.Value) is { } value) answers[ReadingPolicy.Key(match.Value)] = value;
            return projectedExplanation = BridgePresentation.Tokens(new(new("", default), new(Explanation, [])), answers, known, KnowledgeLevel);
        }
    }
    public event Action? Changed;
    public event Action<string>? ReadAloud;
    public event Action<Exception>? Failed;
    public event Action<Exception>? ContextFailed;
    public event Action<string, string>? LemmaFound;
    public bool TranslateMeaning { get; set; } = true;
    public bool TranslateSentence { get; set; } = true;
    public Func<string, int>? KnowledgeLevel { get; set; }
    public Func<HoveredText, CancellationToken, Action<ContextualAnswer>, Task<ContextualAnswer>>? ContextProvider { get; set; }

    public HoverSession(Func<string, string?> cached,
        Func<IReadOnlyList<string>, CancellationToken, Task<IReadOnlyList<string>>> translate, Func<string, bool> known)
    { this.cached = cached; this.translate = translate; this.known = known; }

    public Task FocusAsync(HoveredText hit)
    {
        hit = SentenceWindow.Around(hit);
        if (Current?.Word == hit.Word && Current.Line.Text == hit.Line.Text && Current.FocusOccurrence == hit.FocusOccurrence) return Task.CompletedTask;
        Clear(); var request = pending = new CancellationTokenSource(); Current = hit;
        string word = ReadingPolicy.Words().Match(hit.Word.Text).Value;
        string identity = ReadingPolicy.Key(word);
        helpHistory[identity] = helpHistory.GetValueOrDefault(identity, []).Where(at => DateTimeOffset.Now - at < TimeSpan.FromMinutes(10)).Append(DateTimeOffset.Now).TakeLast(2).ToArray();
        if (helpHistory[identity].Length >= 2 && cooledUnits.Count < 256) cooledUnits.Add(identity);
        if (helpHistory.Count > 256) helpHistory.Remove(helpHistory.Keys.First(key => key != identity));
        var tokens = new[] { word }.Concat(ReadingPolicy.Words().Matches(hit.Line.Text).Select(m => m.Value)).DistinctBy(ReadingPolicy.Key).Take(36).ToArray();
        foreach (string next in tokens)
            if (ReadingPolicy.TryGloss(ReadingPolicy.Glosses, next, out var curated)) glosses[ReadingPolicy.Key(next)] = curated;
            else if (cached(next) is { } meaning) glosses[ReadingPolicy.Key(next)] = meaning;
        Meaning = glosses.GetValueOrDefault(ReadingPolicy.Key(word), "");
        Explanation = DanishLanguage.Shared.Beginner.GetValueOrDefault(ReadingPolicy.Key(word), "");
        Publish(); ReadAloud?.Invoke(word);
        return CompleteOwnedAsync(word, tokens, hit, request);
    }
    private async Task CompleteOwnedAsync(string word, string[] tokens, HoveredText hit, CancellationTokenSource request)
    {
        try { await Task.WhenAll(CompleteWordsAsync(word, tokens, request.Token), CompleteContextAsync(hit, request.Token)); }
        finally { if (ReferenceEquals(pending, request)) pending = null; request.Dispose(); }
    }
    private async Task CompleteWordsAsync(string word, string[] tokens, CancellationToken token)
    {
        try
        {
            if (!TranslateMeaning && !TranslateSentence) return;
            if (Meaning.Length == 0)
            {
                string meaning = (await translate([word], token))[0]; token.ThrowIfCancellationRequested();
                if (!contextualKeys.Contains(ReadingPolicy.Key(word))) { Meaning = meaning; glosses[ReadingPolicy.Key(word)] = meaning; Publish(); }
            }
            await Task.Delay(60, token);
            if (TranslateSentence)
                foreach (var batch in tokens.Where(t => !glosses.ContainsKey(ReadingPolicy.Key(t)) && !known(ReadingPolicy.Key(t))).Chunk(4))
                {
                    token.ThrowIfCancellationRequested(); var values = await translate(batch, token); token.ThrowIfCancellationRequested();
                    for (int i = 0; i < batch.Length; i++) if (!contextualKeys.Contains(ReadingPolicy.Key(batch[i]))) glosses[ReadingPolicy.Key(batch[i])] = values[i];
                    Publish();
                }
            if (TranslateMeaning && Explanation.Length > 0)
                foreach (var batch in ReadingPolicy.Words().Matches(Explanation).Select(m => m.Value).DistinctBy(ReadingPolicy.Key)
                    .Where(w => !known(ReadingPolicy.Key(w)) && !ReadingPolicy.TryGloss(ReadingPolicy.Glosses, w, out _) && cached(w) is null).Take(12).Chunk(4))
                {
                    await translate(batch, token); token.ThrowIfCancellationRequested(); Publish();
                }
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { }
        catch (Exception error) { if (!token.IsCancellationRequested) Failed?.Invoke(error); }
    }
    private async Task CompleteContextAsync(HoveredText hit, CancellationToken token)
    {
        if (ContextProvider is null || !TranslateMeaning && !TranslateSentence) return;
        void Apply(ContextualAnswer answer)
        {
            token.ThrowIfCancellationRequested();
            foreach (var pair in answer.Glosses)
            {
                glosses[pair.Key] = pair.Value; contextualKeys.Add(pair.Key);
                if (PreviousMeaning?.Invoke(pair.Key) is { Length: > 0 } previous && ReadingPolicy.Key(previous) != ReadingPolicy.Key(pair.Value)) newSenseKeys.Add(pair.Key);
            }
            if (answer.Focus.Meaning.Length > 0)
            {
                string key = ReadingPolicy.Key(hit.Word.Text); Meaning = answer.Focus.Meaning;
                glosses[key] = Meaning; contextualKeys.Add(key);
                if (PreviousMeaning?.Invoke(key) is { Length: > 0 } previous && ReadingPolicy.Key(previous) != ReadingPolicy.Key(Meaning)) newSenseKeys.Add(key);
            }
            if (answer.Focus.Explanation.Length > 0) Explanation = answer.Focus.Explanation;
            if (answer.Focus.Lemma.Length > 0) LemmaFound?.Invoke(hit.Word.Text, answer.Focus.Lemma);
            Publish();
        }
        try { Apply(await ContextProvider(hit, token, Apply)); }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { }
        catch (Exception error) { if (!token.IsCancellationRequested) ContextFailed?.Invoke(error); }
    }
    public void InvalidateProjection() { projectedTokens = projectedExplanation = null; }
    private void Publish() { InvalidateProjection(); Changed?.Invoke(); }
    public void Refresh() { visibleAnchors.Clear(); Publish(); }
    public async Task ToggleSentenceMeaningAsync()
    {
        SentenceHelp = !SentenceHelp; Publish();
        if (!SentenceHelp || SentenceMeaning.Length > 0 || Current is not { } hit || sentenceRequest is not null) return;
        using var owner = new CancellationTokenSource(); sentenceRequest = owner;
        try
        {
            var result = await translate([hit.Line.Text], owner.Token);
            owner.Token.ThrowIfCancellationRequested();
            if (ReferenceEquals(sentenceRequest, owner)) { SentenceMeaning = result[0]; Publish(); }
        }
        catch (OperationCanceledException) { }
        catch (Exception) { if (ReferenceEquals(sentenceRequest, owner)) { SentenceMeaning = "Sentence translation is unavailable. Reading remains available."; Publish(); } }
        finally { if (ReferenceEquals(sentenceRequest, owner)) sentenceRequest = null; }
    }
    public void Clear()
    {
        pending?.Cancel(); pending = null; sentenceRequest?.Cancel(); sentenceRequest = null; Current = null; Meaning = ""; Explanation = ""; SentenceMeaning = ""; SentenceHelp = false; glosses = []; contextualKeys.Clear(); InvalidateProjection();
        visibleAnchors.Clear();
        newSenseKeys.Clear();
    }
    public void ResetLearningSession() { helpHistory.Clear(); learningTargets.Clear(); cooledUnits.Clear(); Clear(); }
    public void Dispose() => Clear();
}
