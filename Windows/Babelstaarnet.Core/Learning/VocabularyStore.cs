using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Babelstaarnet.Core;

public sealed class VocabularyEntry
{
    internal VocabularyEntry Snapshot() => (VocabularyEntry)MemberwiseClone();
    public string Key { get; set; } = "";
    public string Word { get; set; } = "";
    public string Meaning { get; set; } = "";
    public string Sentence { get; set; } = "";
    public string? Lemma { get; set; }
    public bool Saved { get; set; }
    public bool Tracked { get; set; } = true;
    public int Level { get; set; }
    public DateTimeOffset SavedAt { get; set; }
    public DateTimeOffset? ReviewedAt { get; set; }
    public int SpacedEncounters { get; set; }
    public DateTimeOffset? LastEncounterAt { get; set; }
    public string LastContext { get; set; } = "";
    public int EncounterCount { get; set; }
    public int MoreEnglishCount { get; set; }
    public int KnownConfirmationCount { get; set; }
    public DateTimeOffset LastSeen { get; set; }
    [JsonIgnore] public DateTimeOffset DueAt => DueDate(DateTimeOffset.Now);
    [JsonIgnore] public string Familiarity => EffectiveLevel(DateTimeOffset.Now) switch
    { 0 => "New word", 1 or 2 => "Learning", 3 or 4 => "Probably understood", _ => "Well established" };
    public DateTimeOffset DueDate(DateTimeOffset now) => (ReviewedAt ?? SavedAt) + ReviewInterval(EffectiveLevel(now));
    public int EffectiveLevel(DateTimeOffset now)
    {
        int level = Tracked ? Level : ReadingPolicy.StructuralWords.Contains(Key) ? 4 : 0;
        if (!Tracked || ReviewedAt is not { } reviewed) return level;
        double elapsed = Math.Max(0, (now - reviewed).TotalDays);
        while (level > 0)
        {
            int retention = level switch { 1 => 7, 2 => 21, 3 => 60, 4 => 180, _ => 365 };
            if (elapsed < retention) break;
            elapsed -= retention; level--;
        }
        return level;
    }
    public static TimeSpan ReviewInterval(int level) => level switch
    { <= 0 => TimeSpan.FromHours(1), 1 => TimeSpan.FromDays(1), 2 => TimeSpan.FromDays(3), 3 => TimeSpan.FromDays(7), 4 => TimeSpan.FromDays(21), _ => TimeSpan.FromDays(60) };
}

public sealed class VocabularyStore
{
    private readonly string path;
    private readonly Dictionary<string, VocabularyEntry> words;
    private int pendingEncounters;
    private DateTimeOffset lastSaved;
    private Task pendingWrite = Task.CompletedTask;
    private readonly Dictionary<string, string> lemmas;
    private bool migratedKeys;
    public const int MaximumEntries = 100_000;
    public const int MaximumSavedEntries = 5000;
    public event Action? Changed;
    public IEnumerable<VocabularyEntry> Saved => words.Values.Where(w => w.Saved).OrderByDescending(w => w.SavedAt);
    public int TrackedCount => words.Values.Count(w => w.Tracked);
    public int FamiliarCount => words.Values.Count(w => w.Tracked && w.EffectiveLevel(DateTimeOffset.Now) >= 4);
    public VocabularyStore(string path)
    {
        this.path = path;
        var entries = File.Exists(path) ? JsonSerializer.Deserialize<List<VocabularyEntry>>(File.ReadAllText(path)) ?? throw new InvalidDataException("The vocabulary file is empty.") : [];
        if (entries.Count > MaximumEntries || entries.Any(e => e is null || string.IsNullOrEmpty(e.Key) || (e.Key != ReadingPolicy.Key(e.Word) && e.Key != ReadingPolicy.FoldKey(e.Word)) || e.Level is < 0 or > 5))
            throw new InvalidDataException("The vocabulary file contains invalid entries.");
        foreach (var entry in entries) { string canonical = ReadingPolicy.Key(entry.Word); migratedKeys |= entry.Key != canonical; entry.Key = canonical; }
        if (entries.Select(e => e.Key).Distinct().Count() != entries.Count) throw new InvalidDataException("The vocabulary file contains duplicate entries.");
        words = entries.ToDictionary(e => e.Key);
        foreach (var entry in entries) entry.EncounterCount = Math.Max(entry.EncounterCount, entry.SpacedEncounters);
        lemmas = File.Exists(path + ".lemmas.json") ? JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(path + ".lemmas.json")) ?? [] : [];
        if (lemmas.Count > 5000 || lemmas.Any(p => p.Key != ReadingPolicy.Key(p.Key) || p.Key.Length is 0 or > 100 || p.Value is null || p.Value.Length is 0 or > 40 || p.Value != ReadingPolicy.Key(p.Value) || p.Value.Any(c => !char.IsLetter(c) && c != '-')))
            throw new InvalidDataException("The dictionary form file contains invalid entries.");
    }
    public bool IsKnown(string key) => EffectiveLevel(key) >= 4;
    public bool LearningCandidate(string key) => words.TryGetValue(ReadingPolicy.Key(key), out var entry) && (entry.Saved || entry.KnownConfirmationCount > 0);
    public IEnumerable<string> RecentLearningUnits(DateTimeOffset now) => words.Values.Where(e =>
        (e.Saved && now - e.SavedAt <= TimeSpan.FromDays(14)) ||
        (e.ReviewedAt is { } reviewed && now - reviewed <= TimeSpan.FromDays(14))).Select(e => e.Key).Take(200);
    public bool LeaveInDanish(string key) => EffectiveLevel(key) >= 3;
    public int EffectiveLevel(string key)
    {
        key = ReadingPolicy.Key(key);
        if (words.TryGetValue(key, out var entry) && entry.Tracked) return entry.EffectiveLevel(DateTimeOffset.Now);
        int prior = ReadingPolicy.StructuralWords.Contains(key) ? 4 : 0;
        return lemmas.TryGetValue(key, out var lemma) && words.TryGetValue(lemma, out var progress) && progress.Tracked
            ? Math.Max(prior, Math.Clamp(progress.EffectiveLevel(DateTimeOffset.Now) - 1, 0, 3)) : prior;
    }
    public void RecordLemma(string form, string lemma)
    {
        string key = ReadingPolicy.Key(form), root = ReadingPolicy.Key(lemma);
        if (key.Length == 0 || root.Length is 0 or > 40 || root.Any(c => !char.IsLetter(c) && c != '-') || root == key || lemmas.GetValueOrDefault(key) == root) return;
        if (lemmas.Count >= 5000) lemmas.Remove(lemmas.Keys.First());
        lemmas[key] = root;
        if (words.TryGetValue(key, out var entry)) entry.Lemma = root;
        Persist();
    }
    public void Observe(string word, string sentence, DateTimeOffset now)
    {
        var entry = Get(word); if (entry is null) return;
        entry.Tracked = true; entry.EncounterCount++; entry.LastSeen = now;
        string context = ContextSignature(sentence);
        if (entry.LastEncounterAt is not { } last || now - last >= TimeSpan.FromHours(20) && (context != entry.LastContext || now - last >= TimeSpan.FromDays(7)))
        {
            entry.SpacedEncounters++; entry.LastEncounterAt = now; entry.LastContext = context;
            if (entry.Level < 4) entry.Level = Math.Max(entry.EffectiveLevel(now), entry.SpacedEncounters switch { <= 1 => 0, <= 3 => 1, <= 6 => 2, _ => 3 });
        }
        pendingEncounters++;
        if (pendingEncounters >= 12 || now - lastSaved >= TimeSpan.FromSeconds(8)) Persist(defer: true); else Changed?.Invoke();
    }
    public void Save(string word, string meaning, string sentence, DateTimeOffset now)
    {
        var entry = Get(word); if (entry is null) return;
        entry.Saved = true; entry.SavedAt = now;
        entry.Lemma = lemmas.GetValueOrDefault(entry.Key) ?? entry.Lemma;
        if (!string.IsNullOrWhiteSpace(meaning) && !string.Equals(meaning, word, StringComparison.OrdinalIgnoreCase)) entry.Meaning = meaning.Trim();
        if (!string.IsNullOrWhiteSpace(sentence)) { string compact = System.Text.RegularExpressions.Regex.Replace(sentence.Trim(), @"\s+", " "); entry.Sentence = compact[..Math.Min(compact.Length, 400)]; }
        foreach (var old in Saved.Skip(MaximumSavedEntries).ToArray()) old.Saved = false;
        Persist();
    }
    public void SetMeaning(string key, string meaning)
    {
        if (words.TryGetValue(ReadingPolicy.Key(key), out var entry) && !string.IsNullOrWhiteSpace(meaning)) { entry.Meaning = meaning.Trim(); Persist(); }
    }
    public void RemoveSaved(string key)
    { key = ReadingPolicy.Key(key); if (words.TryGetValue(key, out var entry)) { entry.Saved = false; if (!entry.Tracked) words.Remove(key); Persist(); } }
    public void Mark(string word, bool known, DateTimeOffset now)
    {
        var entry = Get(word); if (entry is null) return;
        int current = entry.EffectiveLevel(now);
        entry.Level = known ? current < 4 ? 4 : current >= 5 || entry.ReviewedAt is null || now - entry.ReviewedAt >= TimeSpan.FromHours(20) ? 5 : 4 : 0;
        if (known) entry.KnownConfirmationCount++; else { entry.MoreEnglishCount++; ClearSpaced(entry); }
        entry.Tracked = true; entry.LastSeen = now; entry.ReviewedAt = now; Persist();
    }
    public void Review(string key, bool remembered, DateTimeOffset now)
    {
        if (!words.TryGetValue(ReadingPolicy.Key(key), out var entry)) return;
        entry.Level = remembered ? Math.Min(entry.EffectiveLevel(now) + 1, 5) : 0;
        if (remembered) entry.KnownConfirmationCount++; else { entry.MoreEnglishCount++; ClearSpaced(entry); }
        entry.Tracked = true; entry.LastSeen = now; entry.ReviewedAt = now; Persist();
    }
    private static void ClearSpaced(VocabularyEntry e) { e.SpacedEncounters = 0; e.LastEncounterAt = null; e.LastContext = ""; }
    public void ResetLearning()
    {
        lemmas.Clear();
        foreach (var key in words.Where(p => !p.Value.Saved).Select(p => p.Key).ToArray()) words.Remove(key);
        foreach (var entry in words.Values)
        { entry.Tracked = false; entry.Level = ReadingPolicy.StructuralWords.Contains(entry.Key) ? 4 : 0; entry.ReviewedAt = null; entry.EncounterCount = entry.MoreEnglishCount = entry.KnownConfirmationCount = 0; ClearSpaced(entry); }
        Persist();
    }
    private VocabularyEntry? Get(string word)
    {
        string key = ReadingPolicy.Key(word); if (key.Length == 0) return null;
        if (words.TryGetValue(key, out var existing)) return existing;
        if (words.Count >= MaximumEntries)
        { var oldest = words.Values.Where(e => !e.Saved).MinBy(e => e.LastSeen); if (oldest is null) throw new InvalidOperationException("The learning profile is full."); words.Remove(oldest.Key); }
        var entry = new VocabularyEntry { Key = key, Word = word, Level = EffectiveLevel(key), Lemma = lemmas.GetValueOrDefault(key) };
        words[key] = entry; return entry;
    }
    private void Persist(bool defer = false)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        if (migratedKeys && File.Exists(path) && !File.Exists(path + ".pre-unicode.bak")) File.Copy(path, path + ".pre-unicode.bak");
        migratedKeys = false;
        var snapshot = words.Values.Select(e => e.Snapshot()).ToArray(); var lemmaSnapshot = new Dictionary<string, string>(lemmas);
        void Write()
        {
            string temporary = path + ".tmp"; File.WriteAllText(temporary, JsonSerializer.Serialize(snapshot)); File.Move(temporary, path, overwrite: true);
            File.WriteAllText(path + ".lemmas.json.tmp", JsonSerializer.Serialize(lemmaSnapshot)); File.Move(path + ".lemmas.json.tmp", path + ".lemmas.json", overwrite: true);
        }
        var previous = pendingWrite;
        async Task WaitForPrevious()
        {
            // A newer complete snapshot can repair a failed background save.
            try { await previous.ConfigureAwait(false); }
            catch (IOException) { } catch (UnauthorizedAccessException) { }
        }
        if (defer) pendingWrite = Task.Run(async () => { await WaitForPrevious().ConfigureAwait(false); Write(); });
        else { WaitForPrevious().GetAwaiter().GetResult(); Write(); pendingWrite = Task.CompletedTask; }
        pendingEncounters = 0; lastSaved = DateTimeOffset.Now; Changed?.Invoke();
    }
    public void Flush() { if (pendingEncounters > 0) Persist(); pendingWrite.GetAwaiter().GetResult(); }
    public string Csv()
    {
        static string Field(string value) => "\"" + value.Replace("\"", "\"\"") + "\"";
        return "word,dictionary form,meaning,sentence,saved\r\n" + string.Concat(Saved.Select(e => string.Join(",", Field(e.Word), Field(e.Lemma ?? ""), Field(e.Meaning), Field(e.Sentence), e.SavedAt.ToString("yyyy-MM-dd")) + "\r\n"));
    }
    private static string ContextSignature(string text)
    {
        string compact = System.Text.RegularExpressions.Regex.Replace(text.Normalize().ToLowerInvariant().Trim(), @"\s+", " ");
        ulong hash = 14695981039346656037; foreach (byte b in Encoding.UTF8.GetBytes(compact)) { hash ^= b; hash = unchecked(hash * 1099511628211); } return hash.ToString("x");
    }
    private static readonly JsonSerializerOptions ArchiveOptions = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase, WriteIndented = true, Converters = { new ArchiveDateConverter() } };
    public string ExportProfile(DateTimeOffset now)
    {
        var archive = new LearningArchive { SourceLanguage = "da", ExportedAt = now, Words = words.Values.Where(e => e.Tracked).OrderBy(e => e.Word).Select(e => new LearningWord
        {
            Word = ReadingPolicy.Words().Match(e.Word).Value.ToLowerInvariant().Normalize(), KnowledgeLevel = e.Level, Familiarity = e.Level / 5.0,
            EncounterCount = e.EncounterCount, MoreEnglishCount = e.MoreEnglishCount, KnownConfirmationCount = e.KnownConfirmationCount,
            SpacedEncounterCount = e.SpacedEncounters, LastSeen = e.LastSeen == default ? e.ReviewedAt ?? e.LastEncounterAt ?? now : e.LastSeen,
            LastReviewedAt = e.ReviewedAt, LastSpacedEncounterAt = e.LastEncounterAt, LastContextSignature = e.LastContext.Length > 0 ? e.LastContext : null
        }).ToArray() };
        return JsonSerializer.Serialize(archive, ArchiveOptions);
    }
    public int ImportProfile(string json, DateTimeOffset now)
    {
        if (Encoding.UTF8.GetByteCount(json) > 25_000_000) throw new InvalidDataException("This learning profile is too large to import.");
        var archive = JsonSerializer.Deserialize<LearningArchive>(json, ArchiveOptions) ?? throw new InvalidDataException("The profile is empty.");
        if (archive.SchemaVersion != 1) throw new InvalidDataException("Unsupported learning profile version.");
        if (archive.SourceLanguage != "da") throw new InvalidDataException("This learning profile is not for Danish.");
        if (archive.Words is null || archive.Words.Length > MaximumEntries) throw new InvalidDataException("Too many word records.");
        // Validate the entire archive before mutating even one local record.
        foreach (var e in archive.Words)
        {
            if (e is null || string.IsNullOrWhiteSpace(e.Word) || e.Word.Length > 100 || !ReadingPolicy.Words().IsMatch(e.Word) ||
                e.Level is < 0 or > 5 || e.EncounterCount < 0 || e.MoreEnglishCount < 0 || e.KnownConfirmationCount < 0 || e.SpacedEncounterCount < 0 || e.SpacedEncounterCount > e.EncounterCount || (e.LastContextSignature?.Length ?? 0) > 64 || e.LastSeen == default)
                throw new InvalidDataException("The profile contains invalid learning progress.");
        }
        foreach (var incoming in archive.Words)
        {
            var target = Get(incoming.Word)!;
            bool hadProgress = target.Tracked && (target.LastSeen != default || target.ReviewedAt is not null);
            bool incomingReview = !hadProgress || incoming.LastReviewedAt > target.ReviewedAt || target.ReviewedAt is null && incoming.LastReviewedAt is not null;
            bool tied = incoming.LastReviewedAt == target.ReviewedAt;
            int incomingEffective = new VocabularyEntry { Level = incoming.Level, ReviewedAt = incoming.LastReviewedAt }.EffectiveLevel(now);
            if (incomingReview || tied && incomingEffective < target.EffectiveLevel(now)) { target.Level = incoming.Level; target.ReviewedAt = incoming.LastReviewedAt; }
            if (!hadProgress) { target.Level = incoming.Level; target.ReviewedAt = incoming.LastReviewedAt; }
            target.Tracked = true; target.EncounterCount = Math.Max(target.EncounterCount, incoming.EncounterCount);
            target.MoreEnglishCount = Math.Max(target.MoreEnglishCount, incoming.MoreEnglishCount); target.KnownConfirmationCount = Math.Max(target.KnownConfirmationCount, incoming.KnownConfirmationCount);
            target.SpacedEncounters = Math.Max(target.SpacedEncounters, incoming.SpacedEncounterCount); target.LastSeen = target.LastSeen > incoming.LastSeen ? target.LastSeen : incoming.LastSeen;
            if (target.LastEncounterAt is null || incoming.LastSpacedEncounterAt > target.LastEncounterAt)
            { target.LastEncounterAt = incoming.LastSpacedEncounterAt; target.LastContext = incoming.LastContextSignature ?? ""; }
        }
        Persist(); return archive.Words.Length;
    }
}
public sealed class LearningArchive
{
    public int SchemaVersion { get; set; } = 1;
    public string SourceLanguage { get; set; } = "";
    public DateTimeOffset ExportedAt { get; set; }
    public LearningWord[] Words { get; set; } = [];
}
public sealed class LearningWord
{
    public string Word { get; set; } = "";
    public int? KnowledgeLevel { get; set; }
    public double? Familiarity { get; set; }
    [JsonIgnore] public int Level => KnowledgeLevel ?? (Familiarity is >= 0 and <= 1 ? (int)Math.Round(Familiarity.Value * 5) : -1);
    public int EncounterCount { get; set; }
    public int MoreEnglishCount { get; set; }
    public int KnownConfirmationCount { get; set; }
    public int SpacedEncounterCount { get; set; }
    public DateTimeOffset LastSeen { get; set; }
    public DateTimeOffset? LastReviewedAt { get; set; }
    public DateTimeOffset? LastSpacedEncounterAt { get; set; }
    public string? LastContextSignature { get; set; }
}
internal sealed class ArchiveDateConverter : JsonConverter<DateTimeOffset>
{
    public override DateTimeOffset Read(ref Utf8JsonReader reader, Type type, JsonSerializerOptions options) => reader.GetDateTimeOffset();
    public override void Write(Utf8JsonWriter writer, DateTimeOffset value, JsonSerializerOptions options) => writer.WriteStringValue(value.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'"));
}
