using Babelstaarnet.Core;
using Babelstaarnet.Windows;
using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Threading.Tasks;

internal static class ContextualEngineChecks
{
    internal static async Task<int> RunAsync()
    {
        string data = Environment.GetEnvironmentVariable("BABELSTAARNET_ARGOS_TEST_DATA") ?? throw new Exception("Set BABELSTAARNET_ARGOS_TEST_DATA first.");
        using var engine = new ContextualGlossClient(data);
        if (!engine.IsInstalled) throw new Exception("Install local Ollama and Gemma 3 4B before the real contextual check.");
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(3));
        var watch = Stopwatch.StartNew(); await engine.WarmAsync(deadline.Token);
        Console.WriteLine($"Local contextual model warm: {watch.ElapsedMilliseconds} ms");
        HoveredText Hit(string sentence) => new(new("får", new(0, 0, 20, 20)), new(sentence, []));
        var verb = await engine.ExplainAsync(Hit("Han får en gave."), deadline.Token);
        var noun = await engine.ExplainAsync(Hit("Der står får på marken."), deadline.Token);
        Console.WriteLine("Verb: " + verb.Focus + "\nNoun: " + noun.Focus);
        if (!(verb.Focus.Meaning.Contains("get", StringComparison.OrdinalIgnoreCase) || verb.Focus.Meaning.Contains("receiv", StringComparison.OrdinalIgnoreCase)) || !noun.Focus.Meaning.Contains("sheep", StringComparison.OrdinalIgnoreCase))
            throw new Exception("The offline model must distinguish får as gets from får as sheep.");
        if (verb.Focus.Explanation.Length == 0 || noun.Focus.Lemma.Length == 0) throw new Exception("Contextual explanations and dictionary forms must be populated.");
        int before = engine.Generations; await engine.ExplainAsync(Hit("Han får en gave."), deadline.Token);
        if (engine.Generations != before) throw new Exception("Repeated focus in one sentence must reuse contextual caches.");
        File.WriteAllText(Path.Combine(data, "..", "windows-contextual-check.json"), System.Text.Json.JsonSerializer.Serialize(new { verb, noun, cached = true }));
        Console.WriteLine("Real offline contextual meaning, Danish explanation, lemma and cache checks passed.");
        return 0;
    }
}
