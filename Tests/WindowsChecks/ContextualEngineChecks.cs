using Babelstaarnet.Core;
using Babelstaarnet.Windows;
using System;
using System.Collections.Generic;
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
        var question = Hit(ReadingQualityChecks.Question);
        var elapsed = Stopwatch.StartNew(); long firstMeaning = -1;
        var questionAnswer = await engine.ExplainAsync(question, deadline.Token, answer => { if (firstMeaning < 0 && answer.Focus.Meaning.Length > 0) firstMeaning = elapsed.ElapsedMilliseconds; }, includeSentence: false);
        if (!(questionAnswer.Focus.Meaning.Contains("get", StringComparison.OrdinalIgnoreCase) || questionAnswer.Focus.Meaning.Contains("receiv", StringComparison.OrdinalIgnoreCase))) throw new Exception("The reported A2B question must use the verb sense, not sheep.");
        Console.WriteLine($"A2B fixture: {questionAnswer.Focus.Meaning}; first meaning {firstMeaning} ms, complete explanation {elapsed.ElapsedMilliseconds} ms (model-only fixture, no desktop latency).");
        var questionLine = await engine.ExplainAsync(question, deadline.Token);
        Console.WriteLine("A2B contextual line: " + System.Text.Json.JsonSerializer.Serialize(questionLine.Glosses));
        string Gloss(string word) => questionLine.Glosses.GetValueOrDefault(word, "").ToLowerInvariant();
        if (!Gloss("dagen").Contains("day") || !Gloss("aftenen").Contains("evening") ||
            !new[] { "class", "lesson", "teach", "educat", "instruction", "tuition" }.Any(Gloss("undervisning").Contains))
            throw new Exception("The reported question must retain contextual teaching, daytime and evening meanings in the reading line.");
        const string airportText = "Københavns Lufthavn fik påbud om sikkerhed forud for lange køer.";
        var airportWords = await engine.GlossWordsAsync(airportText, ["Københavns", "Lufthavn", "påbud", "sikkerhed", "forud", "lange", "køer"], deadline.Token);
        string queue = airportWords.GetValueOrDefault("køer", "");
        if (!(queue.Contains("queue", StringComparison.OrdinalIgnoreCase) || queue.Contains("line", StringComparison.OrdinalIgnoreCase))) throw new Exception("Airport news must explain køer as queues, not cows.");
        using (var newsReader = new NewsReadingSupport(Path.Combine(fixture, "news")))
        {
            newsReader.WordBands = DanishLanguage.Shared.NewsWordBands;
            newsReader.KnowledgeLevel = word => new[] { "fik", "om", "for" }.Contains(word.ToLowerInvariant()) ? 4 : 0;
            newsReader.CachedWordMeaning = _ => null; newsReader.ContextualWords = engine.GlossWordsAsync;
            var article = new NewsArticle("airport-check", airportText, "", "https://www.dr.dk/nyheder/fixture", 0, 0);
            await newsReader.PrepareAsync(article);
            var pieces = NewsReadingSupport.Pieces(airportText);
            if (!newsReader.Ready(article) || pieces.Count(p => newsReader.Presentation(p, article).Mode == 2) != 1 || newsReader.Presentation("lange", article).Mode != 2)
                throw new Exception("The installed model must supply a readable airport card with just one new basic word.");
            Console.WriteLine("Real mixed news fixture: " + string.Join(' ', pieces.Select(p => newsReader.Presentation(p, article).Text)));
        }
        using var abandoned = new CancellationTokenSource();
        var moved = Hit("Hun får en besked fra skolen.");
        try { await engine.ExplainAsync(moved, abandoned.Token, partial => { if (partial.Focus.Meaning.Length > 0) abandoned.Cancel(); }, includeSentence: false); }
        catch (OperationCanceledException) { }
        await engine.WarmAsync(deadline.Token); // Wait for the owned, already-sent request to drain.
        int afterDrain = engine.Generations;
        var recovered = await engine.ExplainAsync(moved, deadline.Token, includeSentence: false);
        if (engine.Generations != afterDrain || recovered.Focus.Meaning.Length == 0) throw new Exception("Moving away must preserve the in-flight contextual answer in cache.");
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
