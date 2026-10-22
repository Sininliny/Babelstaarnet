using Babelstaarnet.Core;
using Babelstaarnet.Windows;
using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

internal static class ContextualEngineChecks
{
    internal static async Task<int> RunAsync()
    {
        string data = Environment.GetEnvironmentVariable("BABELSTAARNET_ARGOS_TEST_DATA") ?? throw new Exception("Set BABELSTAARNET_ARGOS_TEST_DATA first.");
        string fixture = Path.Combine(data, "..", "context-check-" + Guid.NewGuid().ToString("N"));
        using var engine = new ContextualGlossClient(fixture);
        if (!engine.IsInstalled) throw new Exception("Install local Ollama and Gemma 3 4B before the real contextual check.");
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(3));
        var watch = Stopwatch.StartNew(); await engine.WarmAsync(deadline.Token);
        Console.WriteLine($"Local contextual model warm: {watch.ElapsedMilliseconds} ms");
        HoveredText Hit(string sentence) => new(new("får", new(0, 0, 20, 20)), new(sentence, []));
        var verb = await engine.ExplainAsync(Hit("Han får en gave."), deadline.Token, includeSentence: false);
        if (engine.Generations != 1) throw new Exception("Word-only mode must make only the focused request.");
        await engine.ExplainAsync(Hit("Han får en gave."), deadline.Token, includeSentence: true, leaveInDanish: key => key != "gave");
        if (engine.Generations != 2) throw new Exception("Sentence enrichment must reuse the focused result and skip familiar words.");
        var noun = await engine.ExplainAsync(Hit("Der står får på marken."), deadline.Token, includeSentence: false);
        Console.WriteLine("Verb: " + verb.Focus + "\nNoun: " + noun.Focus);
        if (!(verb.Focus.Meaning.Contains("get", StringComparison.OrdinalIgnoreCase) || verb.Focus.Meaning.Contains("receiv", StringComparison.OrdinalIgnoreCase)) || !noun.Focus.Meaning.Contains("sheep", StringComparison.OrdinalIgnoreCase))
            throw new Exception("The offline model must distinguish får as gets from får as sheep.");
        if (verb.Focus.Explanation.Length == 0 || noun.Focus.Lemma.Length == 0) throw new Exception("Contextual explanations and dictionary forms must be populated.");
        int before = engine.Generations; await engine.ExplainAsync(Hit("Han får en gave."), deadline.Token, includeSentence: false);
        if (engine.Generations != before) throw new Exception("Repeated focus in one sentence must reuse contextual caches.");
        engine.Dispose();
        using var restarted = new ContextualGlossClient(fixture);
        var remembered = await restarted.ExplainAsync(Hit("Han får en gave."), deadline.Token, includeSentence: false);
        if (restarted.Generations != 0 || remembered.Focus != verb.Focus) throw new Exception("Restarted context must answer from disk before starting the model.");
        const string excerpt = "Regeringen vil bruge 20 millioner kroner på grøn energi.";
        string simplified = await restarted.SimplifyPublicExcerptAsync(excerpt, deadline.Token);
        if (string.IsNullOrWhiteSpace(simplified)) throw new Exception("Local RSS excerpt generation returned no text.");
        bool displayAllowed = SharedPolicy.SummaryValid(excerpt, simplified, DanishLanguage.Shared.MeaningPreservationWords);
        if (!displayAllowed) throw new Exception("The controlled Danish excerpt must preserve its language and facts before display.");
        Console.WriteLine("Local excerpt generation completed; conservative display check: " + displayAllowed + "\nFixture short version: " + simplified);
        using (var cancelNews = new CancellationTokenSource(TimeSpan.FromMilliseconds(100)))
        {
            var cancellationWatch = Stopwatch.StartNew();
            try { await restarted.SimplifyPublicExcerptAsync(string.Join(" ", Enumerable.Repeat(excerpt, 20)), cancelNews.Token); throw new Exception("Canceled news inference completed unexpectedly."); }
            catch (OperationCanceledException) { }
            if (cancellationWatch.Elapsed > TimeSpan.FromSeconds(5)) throw new Exception("News inference must release the local model promptly for reading.");
            Console.WriteLine("Owned news model process yielded to cancellation.");
        }
        File.WriteAllText(Path.Combine(data, "..", "windows-contextual-check.json"), System.Text.Json.JsonSerializer.Serialize(new { verb, noun, cached = true }));
        Console.WriteLine("Real offline contextual meaning, Danish explanation, lemma and cache checks passed.");
        return 0;
    }
}
