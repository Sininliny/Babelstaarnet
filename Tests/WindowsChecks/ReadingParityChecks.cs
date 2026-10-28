using Babelstaarnet.Core;
using Babelstaarnet.Windows;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

internal static class ReadingParityChecks
{
    private static int checks;
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); checks++; }
    internal static int Run(string directory)
    {
        int before = checks;
        Check(ReadingPolicy.Key(" Æbler! ") == "æbler" && ReadingPolicy.Key("får") != ReadingPolicy.Key("far"), "Learning identities must preserve Danish spelling as on Mac.");
        Check(ReadingPolicy.TryGloss(ReadingPolicy.Glosses, "være", out var meaning) && meaning.Length > 0, "Curated source data must support Danish spelling.");
        Check(SentenceBoundary.EndsSentence("Han sagde “nej.”") && SentenceBoundary.EndsSentence("Hvad gør vi?"), "Quotes and questions must close the focused sentence.");
        Check(!SentenceBoundary.EndsSentence("Fristen er den 15.") && !SentenceBoundary.EndsSentence("Det kunne fx være støtte til"), "Dates and incomplete lines must not close a sentence.");
        Check(SentenceBoundary.StopLocations("Se mere på www.au.dk. Fristen er fast.").Count == 2, "Domain and sentence periods must be distinguished.");
        Check(SentenceBoundary.StopLocations("Vi mødes den 15. november kl. 10.30 på AU.").Count == 1, "Danish dates, abbreviations and decimals must retain one sentence.");
        RecognizedLine Line(string text, int y, int x = 100, int height = 20) => new(text, ReadingPolicy.Words().Matches(text).Select((m, i) => new RecognizedWord(m.Value, new(x + i * 40, y, 38, height))).ToArray());
        var a = Line("Det kunne fx være oplysningskampagner, støtte til", 100);
        var b = Line("underrepræsenterede grupper, tilgængelighed i digitale", 130);
        var c = Line("læringsmiljøer og lige adgang til mobilitetsmidler.", 160);
        var d = Line("Andre emner er også velkomne.", 190);
        var hit = ReadingContext.Assemble(new(b.Words[^1], b), [a, b, c, d]);
        Check(hit.Line.Text == a.Text + " " + b.Text + " " + c.Text, "The sentence must join three continuation lines and exclude the next sentence.");
        var mixed = Line("Fristen er fast. Emnerne kan spænde", 100); var next = Line("bredt over mange fag.", 130);
        Check(ReadingContext.Assemble(new(mixed.Words[^1], mixed), [mixed, next]).Line.Text == "Emnerne kan spænde bredt over mange fag.", "A mixed OCR line must select the focused sentence.");
        Check(ReadingContext.Assemble(new(mixed.Words[0], mixed), [mixed, next]).Line.Text == "Fristen er fast.", "The earlier sentence must exclude later text on the same line.");
        var heading = Line("En meget stor overskrift", 45, height: 44); var column = Line("Anden kolonne", 130, x: 900);
        Check(!ReadingContext.Assemble(new(a.Words[0], a), [a, b, c, heading, column]).Line.Text.Contains("overskrift"), "Heading scale and column geometry must constrain context.");
        var first = Line("Et land og et andet", 100); var second = Line("land blev nævnt.", 130);
        var repeated = ReadingContext.Assemble(new(second.Words[0], second), [first, second]);
        var tokens = BridgePresentation.Tokens(repeated, new Dictionary<string, string> { ["land"] = "country" }, _ => false);
        Check(repeated.FocusOccurrence == 1 && tokens.Count(t => t.Focus) == 1 && tokens.Single(t => t.Focus).Text == "country", "Only the pointed occurrence may receive the focus rule.");
        var longText = string.Join(' ', Enumerable.Range(0, 80).Select(i => i == 65 ? "fokus" : "ord"));
        var window = SentenceWindow.Around(new(new("fokus", default), new(longText, [])));
        Check(ReadingPolicy.Words().Matches(window.Line.Text).Count <= 36 && window.Line.Text.Contains("fokus") && window.Line.Text.EndsWith('.'), "Long context must remain bounded around the actual focus.");
        var caseTokens = BridgePresentation.Tokens(new(new("spiser", default), new("Han spiser æbler", [])), new Dictionary<string, string> { ["han"] = "he", ["spiser"] = "Eats" }, _ => false);
        Check(caseTokens[0].Text == "He" && caseTokens[1].Text == "eats", "English substitutions must borrow Danish sentence capitalization.");
        Check(DanishLanguage.KnowledgeOpacity(0) == 1 && Math.Abs(DanishLanguage.KnowledgeOpacity(5) - .9) < .0001, "Danish familiarity fading must match Mac.");
        var now = DateTimeOffset.Now; var memory = new FeedbackMemory(); memory.Remember("Æbler", true, now);
        Check(memory.Recall("æbler", now.AddMinutes(4)) == true && memory.Recall("æbler", now.AddMinutes(5)) is null, "Feedback confirmation must survive revisiting for five minutes.");
        var crop = AdaptiveCapture.Plan(new(700, 500), new(0, 0, 1920, 1080));
        var large = AdaptiveCapture.Plan(new(-800, 0), new(-1920, -400, 1920, 1080), textHeight: 80, scale: 1.5);
        Check(crop.Contains(new(1160, 510)) && crop.Height == 250 && large.X >= -1920 && large.Right <= 0 && large.Y >= -400, "Windows capture must include a short question after an early focus and remain inside scaled displays.");
        Check(AdaptiveCapture.NeedsExpansion([], crop) && !AdaptiveCapture.NeedsExpansion([a], crop), "Sparse crops must expand once while complete text stays bounded.");
        string path = Path.Combine(directory, "lemma-progress.json"); var store = new VocabularyStore(path);
        store.Mark("læse", true, now); store.RecordLemma("læser", "læse");
        Check(store.EffectiveLevel("læser") == 3, "A known dictionary form must transfer limited familiarity to unseen inflections.");
        store.Mark("læser", false, now);
        Check(store.EffectiveLevel("læser") == 0 && new VocabularyStore(path).EffectiveLevel("læser") == 0, "Explicit unknown feedback must override inherited familiarity across restart.");
        store.Save("læser", "reads", "Hun læser.", now); store.ResetLearning();
        Check(store.EffectiveLevel("læser") == 0 && store.Saved.Single().Lemma == "læse", "Reset must clear learning associations while preserving Word Book dictionary forms.");
        string legacyPath = Path.Combine(directory, "legacy-progress.json");
        string legacy = JsonSerializer.Serialize(new[] { new VocabularyEntry { Key = "faer", Word = "fær", Level = 4, Tracked = true } });
        File.WriteAllText(legacyPath, legacy); var migrated = new VocabularyStore(legacyPath); migrated.Mark("fær", true, now);
        Check(migrated.IsKnown("fær") && !migrated.IsKnown("faer") && File.ReadAllText(legacyPath + ".pre-unicode.bak") == legacy, "Legacy key migration must preserve evidence and create an untouched backup.");
        string cache = Path.Combine(directory, "memory.json"); TranslationMemory.Save(cache, "model-a", new() { ["æbler"] = "apples" });
        Check(TranslationMemory.Load(cache, "model-a")["æbler"] == "apples" && TranslationMemory.Load(cache, "model-b").Count == 0, "Translation memory must survive restart and reject a changed model stamp.");
        File.WriteAllText(cache, "{\"Stamp\":\"model-a\",\"Words\":null}");
        Check(TranslationMemory.Load(cache, "model-a").Count == 0, "A malformed cache must not prevent startup.");
        var parsed = ContextualGlossClient.ParseFocus("1. får = receives\nopslagsform: få\nforklaring: At modtage noget", "får");
        Check(parsed.Meaning == "receives" && parsed.Lemma == "få" && parsed.Explanation == "At modtage noget.", "Local contextual replies must use the Mac Danish prompt fields.");
        Check(ContextualGlossClient.ParseGlosses("1. forkert = wrong\n2. mælk = milk", ["æbler", "mælk"]).Count == 1, "A model reply must not attach another word's meaning to the focus.");
        return checks - before;
    }
    internal static async Task<int> SessionAsync()
    {
        int before = checks;
        var delayed = new TaskCompletionSource<ContextualAnswer>(TaskCreationOptions.RunContinuationsAsynchronously);
        using var session = new HoverSession(_ => null, (words, _) => Task.FromResult<IReadOnlyList<string>>(words.Select(w => "fallback").ToArray()), _ => false);
        session.TranslateSentence = false; session.ContextProvider = (hit, token, ready) => delayed.Task; int failures = 0; session.ContextFailed += _ => failures++;
        var first = session.FocusAsync(new(new("får", new(0, 0, 20, 20)), new("Han får en gave.", [])));
        session.ContextProvider = null;
        var second = session.FocusAsync(new(new("marken", new(100, 0, 40, 20)), new("marken", [])));
        delayed.SetResult(new(new Dictionary<string, string> { ["får"] = "receives" }, new("receives", "få", "At modtage noget.")));
        await Task.WhenAll(first, second);
        Check(session.Current?.Word.Text == "marken" && session.Meaning != "receives" && failures == 0, "An abandoned contextual answer must never overwrite the next word or report a cancellation as failure.");
        session.ContextProvider = (_, _, _) => throw new IOException("Model unavailable");
        await session.FocusAsync(new(new("aflysninger", default), new("aflysninger", [])));
        Check(session.Meaning == "fallback" && failures == 1, "Contextual failure must preserve ordinary offline word translation.");
        bool familiar = false;
        using var projection = new HoverSession(_ => "apples", (words, _) => Task.FromResult<IReadOnlyList<string>>(words.Select(_ => "apples").ToArray()), _ => familiar) { TranslateSentence = false };
        await projection.FocusAsync(new(new("æbler", default), new("æbler", [])));
        var firstProjection = projection.Tokens;
        Check(ReferenceEquals(firstProjection, projection.Tokens), "Repeated presentation must reuse its projected sentence tokens.");
        familiar = true; projection.Refresh();
        Check(!projection.Tokens.Single().English && !ReferenceEquals(firstProjection, projection.Tokens), "Feedback must invalidate projection and immediately restore Danish.");
        return checks - before;
    }
}
