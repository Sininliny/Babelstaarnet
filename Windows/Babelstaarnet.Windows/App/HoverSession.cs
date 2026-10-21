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
    private Dictionary<string, string> glosses = [];
    private readonly HashSet<string> contextualKeys = [];
    private IReadOnlyList<BridgeToken>? projectedTokens, projectedExplanation;
    public HoveredText? Current { get; private set; }
    public string Meaning { get; private set; } = "";
    public string Explanation { get; private set; } = "";
    public bool Loading => Current is not null && Meaning.Length == 0;
    public string Bridge => string.Join(' ', Tokens.Select(t => t.Text));
    public IReadOnlyList<BridgeToken> Tokens => projectedTokens ??= Current is null ? [] : BridgePresentation.Tokens(Current, glosses, known, KnowledgeLevel);
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
            foreach (var pair in answer.Glosses) { glosses[pair.Key] = pair.Value; contextualKeys.Add(pair.Key); }
            if (answer.Focus.Meaning.Length > 0) { Meaning = answer.Focus.Meaning; glosses[ReadingPolicy.Key(hit.Word.Text)] = Meaning; contextualKeys.Add(ReadingPolicy.Key(hit.Word.Text)); }
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
    public void Refresh() => Publish();
    public void Clear()
    {
        pending?.Cancel(); pending = null; Current = null; Meaning = ""; Explanation = ""; glosses = []; contextualKeys.Clear(); InvalidateProjection();
    }
    public void Dispose() => Clear();
}
