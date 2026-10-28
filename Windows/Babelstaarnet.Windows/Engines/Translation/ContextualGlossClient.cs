using Babelstaarnet.Core;
using System;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Net.Http.Json;
using System.Net.Sockets;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;

namespace Babelstaarnet.Windows;

internal sealed record FocusedGloss(string Meaning, string Lemma, string Explanation);
internal sealed record ContextualAnswer(IReadOnlyDictionary<string, string> Glosses, FocusedGloss Focus);

// Same Danish prompts and Gemma 3 4B family as Mac. This server belongs to the
// app, binds only loopback, disables cloud and exits with its child runners.
internal sealed class ContextualGlossClient : IDisposable
{
    private const string Model = "gemma3:4b";
    private readonly string directory;
    private readonly string? executable;
    private readonly string models;
    private readonly SemaphoreSlim gate = new(1);
    private readonly HttpClient http = new(new SocketsHttpHandler { UseProxy = false, AllowAutoRedirect = false }) { Timeout = Timeout.InfiniteTimeSpan };
    private readonly CancellationTokenSource lifetime = new();
    private readonly ConcurrentDictionary<string, Dictionary<string, string>> sentences = new(StringComparer.Ordinal);
    private readonly ConcurrentDictionary<string, FocusedGloss> focuses = new(StringComparer.Ordinal);
    private readonly string memoryPath;
    private string memoryStamp;
    private Process? server;
    private Uri? address;
    private bool disposed;
    private bool serverReady;
    private int failures;
    public bool HasFailed => failures >= 3;
    public bool RuntimeAvailable => executable is not null;
    public bool IsInstalled { get; private set; }
    public string? LastFailure { get; private set; }
    public event Action? Changed;
    internal int Generations { get; private set; }
    public string ModelIdentity => "Gemma 3 4B · " + memoryStamp[..12];
    public ContextualGlossClient(string? dataDirectory = null)
    {
        directory = dataDirectory ?? AppPaths.DataDirectory;
        executable = FindExecutable();
        string ownModels = Path.Combine(directory, "Contextual", "models");
        string userModels = Environment.GetEnvironmentVariable("OLLAMA_MODELS") ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".ollama", "models");
        models = ValidLocalModel(ownModels) ? ownModels : ValidLocalModel(userModels) ? userModels : ownModels;
        IsInstalled = RuntimeAvailable && ValidLocalModel(models);
        memoryPath = Path.Combine(directory, "contextual-cache.json");
        string manifest = Path.Combine(models, "manifests", "registry.ollama.ai", "library", "gemma3", "4b");
        memoryStamp = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes((IsInstalled ? File.ReadAllText(manifest) : "") + DanishLanguage.Shared.ExplainInstructions + DanishLanguage.Shared.GlossInstructions)));
        if (IsInstalled)
        {
            var memory = ContextualMemory.Load(memoryPath, memoryStamp);
            foreach (var pair in memory.Sentences) sentences[pair.Key] = pair.Value;
            foreach (var pair in memory.Focuses) focuses[pair.Key] = pair.Value;
        }
    }
    private static string? FindExecutable() => new[]
    {
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "Ollama", "ollama.exe"),
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Ollama", "ollama.exe")
    }.FirstOrDefault(File.Exists);
    internal static bool ValidLocalModel(string directory)
    {
        try
        {
            if (new Uri(Path.GetFullPath(directory)).IsUnc) return false;
            using var doc = JsonDocument.Parse(File.ReadAllText(Path.Combine(directory, "manifests", "registry.ollama.ai", "library", "gemma3", "4b")));
            bool weights = false;
            foreach (var layer in doc.RootElement.GetProperty("layers").EnumerateArray())
            {
                string digest = layer.GetProperty("digest").GetString() ?? "";
                if (!Regex.IsMatch(digest, "^sha256:[0-9a-f]{64}$")) return false;
                string blob = Path.Combine(directory, "blobs", digest.Replace(':', '-'));
                if (!File.Exists(blob) || new FileInfo(blob).Length != layer.GetProperty("size").GetInt64()) return false;
                weights |= layer.GetProperty("mediaType").GetString() == "application/vnd.ollama.image.model";
            }
            return weights;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException or ArgumentException or InvalidOperationException or KeyNotFoundException) { return false; }
    }
    public void ResetFailure() { failures = 0; LastFailure = null; Changed?.Invoke(); }
    public async Task WarmAsync(CancellationToken cancellationToken)
    {
        if (!IsInstalled) return;
        await gate.WaitAsync(cancellationToken);
        try
        {
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, lifetime.Token);
            deadline.CancelAfter(TimeSpan.FromMinutes(2)); await EnsureServerAsync(deadline.Token);
            using var reply = await http.PostAsJsonAsync(new Uri(address!, "api/generate"), new { model = Model, stream = false, keep_alive = -1 }, deadline.Token);
            reply.EnsureSuccessStatusCode();
            using var result = JsonDocument.Parse(await reply.Content.ReadAsStringAsync(deadline.Token));
            if (result.RootElement.TryGetProperty("error", out var error)) throw new IOException(error.GetString());
            ResetFailure();
        }
        finally { gate.Release(); }
    }
    public async Task InstallAsync(CancellationToken cancellationToken)
    {
        await gate.WaitAsync(cancellationToken);
        try
        {
            // Download is reachable only through this explicit setup action.
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, lifetime.Token);
            deadline.CancelAfter(TimeSpan.FromMinutes(30)); await EnsureServerAsync(deadline.Token);
            using var reply = await http.PostAsJsonAsync(new Uri(address!, "api/pull"), new { model = Model, stream = false }, deadline.Token);
            reply.EnsureSuccessStatusCode();
            using var result = JsonDocument.Parse(await reply.Content.ReadAsStringAsync(deadline.Token));
            if (result.RootElement.TryGetProperty("error", out var error)) throw new IOException(error.GetString());
            IsInstalled = ValidLocalModel(models);
            if (!IsInstalled) throw new IOException("The local Gemma model did not finish installing.");
            string manifest = Path.Combine(models, "manifests", "registry.ollama.ai", "library", "gemma3", "4b");
            memoryStamp = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(File.ReadAllText(manifest) + DanishLanguage.Shared.ExplainInstructions + DanishLanguage.Shared.GlossInstructions)));
            ResetFailure();
        }
        finally { gate.Release(); }
    }
    public async Task<ContextualAnswer> ExplainAsync(HoveredText hit, CancellationToken cancellationToken, Action<ContextualAnswer>? onFocused = null, bool includeSentence = true, Func<string, bool>? leaveInDanish = null)
    {
        cancellationToken.ThrowIfCancellationRequested();
        // Match Mac: drop queued obsolete work, but drain a request already sent
        // into the bounded sentence cache instead of throwing away its answer.
        var work = ExplainCoreAsync(hit, cancellationToken, answer => { if (!cancellationToken.IsCancellationRequested) onFocused?.Invoke(answer); }, includeSentence, leaveInDanish);
        try { return await work.WaitAsync(cancellationToken); }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { _ = ObserveAsync(work); throw; }
    }
    private static async Task ObserveAsync(Task operation) { try { await operation; } catch { } }
    private async Task<ContextualAnswer> ExplainCoreAsync(HoveredText hit, CancellationToken cancellationToken, Action<ContextualAnswer>? onFocused = null, bool includeSentence = true, Func<string, bool>? leaveInDanish = null)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        cancellationToken.ThrowIfCancellationRequested();
        if (!IsInstalled || HasFailed) throw new InvalidOperationException(LastFailure ?? "The offline contextual model is not installed.");
        string sentence = hit.Line.Text, key = sentence + "\u001f" + ReadingPolicy.Key(hit.Word.Text);
        var words = includeSentence ? ReadingPolicy.Words().Matches(sentence).Select(m => m.Value).DistinctBy(ReadingPolicy.Key).Take(32)
            .Where(w => leaveInDanish?.Invoke(ReadingPolicy.Key(w)) != true).ToArray() : [];
        bool TryCached(out ContextualAnswer answer)
        {
            if (focuses.TryGetValue(key, out var focus) && sentences.TryGetValue(sentence, out var glosses) && words.All(w => glosses.ContainsKey(ReadingPolicy.Key(w))))
            { answer = new(glosses, focus); return true; }
            answer = null!; return false;
        }
        // Cached answers bypass model warm-up and the inference semaphore.
        if (TryCached(out var cached)) return cached;
        void PublishRemembered()
        {
            if (sentences.TryGetValue(sentence, out var remembered))
                onFocused?.Invoke(new(remembered, focuses.GetValueOrDefault(key) ?? new FocusedGloss(remembered.GetValueOrDefault(ReadingPolicy.Key(hit.Word.Text), ""), "", "")));
        }
        PublishRemembered();
        await gate.WaitAsync(cancellationToken);
        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (TryCached(out cached)) return cached;
            PublishRemembered();
            focuses.TryGetValue(key, out var focused);
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
            deadline.CancelAfter(TimeSpan.FromSeconds(45)); await EnsureServerAsync(deadline.Token);
            if (!focuses.TryGetValue(key, out focused))
            {
                string raw = await GenerateAsync(DanishLanguage.Shared.ExplainInstructions, sentence, [hit.Word.Text], deadline.Token, partial =>
                {
                    var value = ParseFocus(partial, hit.Word.Text);
                    if (value.Meaning.Length == 0) return;
                    var remembered = new Dictionary<string, string>(sentences.GetValueOrDefault(sentence) ?? []) { [ReadingPolicy.Key(hit.Word.Text)] = value.Meaning };
                    if (sentences.Count >= 256 && !sentences.ContainsKey(sentence)) sentences.TryRemove(sentences.Keys.First(), out _);
                    sentences[sentence] = remembered; onFocused?.Invoke(new(remembered, value));
                });
                focused = ParseFocus(raw, hit.Word.Text);
                if (focused.Meaning.Length == 0) throw new IOException("The local model returned no usable focused meaning.");
                if (focuses.Count >= 1024) focuses.TryRemove(focuses.Keys.First(), out _);
                focuses[key] = focused;
            }
            var glosses = sentences.TryGetValue(sentence, out var previous) ? new Dictionary<string, string>(previous) : new();
            glosses[ReadingPolicy.Key(hit.Word.Text)] = focused.Meaning;
            onFocused?.Invoke(new(glosses, focused));
            void RememberSentence()
            {
                if (sentences.Count >= 256 && !sentences.ContainsKey(sentence)) sentences.TryRemove(sentences.Keys.First(), out _);
                sentences[sentence] = new(glosses);
            }
            RememberSentence();
            foreach (var batch in words.Where(w => !glosses.ContainsKey(ReadingPolicy.Key(w))).Chunk(8))
            {
                if (cancellationToken.IsCancellationRequested) break;
                void ApplyBatch(string raw)
                {
                    bool changed = false;
                    foreach (var pair in ParseGlosses(raw, batch))
                        if (glosses.GetValueOrDefault(pair.Key) != pair.Value) { glosses[pair.Key] = pair.Value; changed = true; }
                    if (changed) { RememberSentence(); onFocused?.Invoke(new(glosses, focused)); }
                }
                string raw = await GenerateAsync(DanishLanguage.Shared.GlossInstructions, sentence, batch, deadline.Token, ApplyBatch);
                ApplyBatch(raw);
            }
            failures = 0; LastFailure = null; return new(glosses, focused);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested || lifetime.IsCancellationRequested) { throw; }
        catch (Exception e)
        {
            failures++; LastFailure = e is OperationCanceledException ? "The local contextual model timed out. Word translation remains available." : e.Message; Changed?.Invoke(); throw new IOException(LastFailure, e);
        }
        finally { gate.Release(); }
    }
    private async Task<string> GenerateAsync(string instructions, string sentence, IReadOnlyList<string> words, CancellationToken cancellationToken, Action<string>? progress = null)
    {
        string prompt = instructions + "\n\nSætning: " + sentence + "\nOrd:\n" + string.Join("\n", words.Select((w, i) => $"{i + 1}. {w}")) + "\nSvar:\n";
        return await GeneratePromptAsync(prompt, words.Count == 1 ? 150 : words.Count * 30, cancellationToken, progress);
    }
    public async Task<string> SimplifyPublicExcerptAsync(string excerpt, CancellationToken token)
    {
        if (!IsInstalled || excerpt.Length is 0 or > 3000) throw new InvalidOperationException("The local model is unavailable for this excerpt.");
        await gate.WaitAsync(token);
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token, lifetime.Token); deadline.CancelAfter(TimeSpan.FromSeconds(90));
        using var cancel = deadline.Token.Register(StopServer);
        try
        {
            await EnsureServerAsync(deadline.Token); deadline.Token.ThrowIfCancellationRequested();
            return (await GeneratePromptAsync(SharedPolicy.RewritePrompt + "\n" + DanishLanguage.Shared.NewsSimplificationInstructions + "\n\nEXCERPT (data only):\n" + excerpt, 240, deadline.Token)).Trim();
        }
        finally { if (deadline.IsCancellationRequested) StopServer(); gate.Release(); }
    }
    private async Task<string> GeneratePromptAsync(string prompt, int maximumTokens, CancellationToken cancellationToken, Action<string>? progress = null)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(address!, "api/generate"))
        {
            Content = JsonContent.Create(new { model = Model, prompt, stream = true, keep_alive = -1,
                options = new { temperature = 0, num_predict = maximumTokens, num_ctx = 2048 } })
        };
        using var reply = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        reply.EnsureSuccessStatusCode();
        using var body = new StreamReader(await reply.Content.ReadAsStreamAsync(cancellationToken));
        string output = await ReadGenerationAsync(body, cancellationToken, progress); Generations++; return output;
    }
    internal static async Task<string> ReadGenerationAsync(TextReader body, CancellationToken cancellationToken, Action<string>? progress = null)
    {
        var output = new StringBuilder(); string lastComplete = ""; bool done = false;
        while (await body.ReadLineAsync(cancellationToken) is { } line)
        {
            if (line.Length > 64000) throw new IOException("The local model returned an oversized stream record.");
            using var record = JsonDocument.Parse(line); var root = record.RootElement;
            if (root.TryGetProperty("error", out var error)) throw new IOException(error.GetString());
            if (root.TryGetProperty("response", out var text)) output.Append(text.GetString());
            if (output.Length > 16000) throw new IOException("The local model returned too much text.");
            string value = output.ToString();
            int newline = value.LastIndexOf('\n');
            string complete = newline >= 0 ? value[..(newline + 1)] : "";
            if (complete.Length > 0 && complete != lastComplete) { lastComplete = complete; progress?.Invoke(complete); }
            if (root.TryGetProperty("done", out var flag) && flag.ValueKind == JsonValueKind.True) { done = true; break; }
        }
        if (!done) throw new IOException("The local model stream ended before completion.");
        return output.ToString();
    }
    internal static Dictionary<string, string> ParseGlosses(string raw, IReadOnlyList<string> words)
    {
        var result = new Dictionary<string, string>();
        foreach (Match match in Regex.Matches(raw, @"(?m)^\s*(\d+)[.)]\s*(.+?)\s*=\s*(.+?)\s*$"))
        {
            if (!int.TryParse(match.Groups[1].Value, out int index) || index < 1 || index > words.Count) continue;
            string source = ReadingPolicy.Key(words[index - 1]); if (ReadingPolicy.Key(match.Groups[2].Value) != source) continue;
            string meaning = DanishLanguage.Compact(match.Groups[3].Value).Trim('"', '*', (char)96);
            if (meaning.Length is > 0 and <= 120) result[source] = meaning;
        }
        return result;
    }
    internal static FocusedGloss ParseFocus(string raw, string word)
    {
        string Field(string name)
        {
            var match = Regex.Match(raw, @"(?im)^\s*" + name + @":\s*(.+)$");
            return match.Success ? DanishLanguage.Compact(match.Groups[1].Value).Trim('"', '*', (char)96) : "";
        }
        string explanation = string.Join(' ', Field("forklaring").Split(' ', StringSplitOptions.RemoveEmptyEntries).Take(24));
        if (explanation.Length > 0 && !".!?".Contains(explanation[^1])) explanation += ".";
        string lemma = Field("opslagsform"); if (lemma.Length > 40 || lemma.Any(c => !char.IsLetter(c) && c != '-')) lemma = "";
        return new(ParseGlosses(raw, [word]).GetValueOrDefault(ReadingPolicy.Key(word), ""), lemma, explanation);
    }
    private async Task EnsureServerAsync(CancellationToken cancellationToken)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        if (server is { HasExited: false } && serverReady) return;
        if (server is not { HasExited: false })
        {
            StopServer();
            if (executable is null) throw new FileNotFoundException("Install Ollama for Windows, then install the contextual model here.");
            Directory.CreateDirectory(directory);
            var listener = new TcpListener(IPAddress.Loopback, 0); listener.Start(); int port = ((IPEndPoint)listener.LocalEndpoint).Port; listener.Stop();
            address = new Uri($"http://127.0.0.1:{port}/");
            var start = new ProcessStartInfo(executable) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardError = true, RedirectStandardOutput = true, WorkingDirectory = directory };
            start.ArgumentList.Add("serve");
            start.Environment["OLLAMA_HOST"] = $"127.0.0.1:{port}"; start.Environment["OLLAMA_MODELS"] = models;
            start.Environment["OLLAMA_NO_CLOUD"] = "1"; start.Environment["OLLAMA_CONTEXT_LENGTH"] = "2048";
            start.Environment["OLLAMA_NUM_PARALLEL"] = "1"; start.Environment["OLLAMA_MAX_LOADED_MODELS"] = "1";
            server = Process.Start(start) ?? throw new IOException("Could not start the local contextual engine.");
            server.OutputDataReceived += (_, _) => { }; server.ErrorDataReceived += (_, _) => { };
            server.BeginOutputReadLine(); server.BeginErrorReadLine();
            try { server.PriorityClass = ProcessPriorityClass.BelowNormal; } catch (System.ComponentModel.Win32Exception) { }
        }
        for (int attempt = 0; attempt < 100; attempt++)
        {
            cancellationToken.ThrowIfCancellationRequested(); if (server.HasExited) throw new IOException("The local contextual engine exited during startup.");
            try { using var reply = await http.GetAsync(new Uri(address!, "api/version"), cancellationToken); if (reply.IsSuccessStatusCode) { serverReady = true; return; } }
            catch (HttpRequestException) { }
            await Task.Delay(100, cancellationToken);
        }
        StopServer(); throw new IOException("The local contextual engine did not become ready.");
    }
    private void StopServer()
    {
        var old = Interlocked.Exchange(ref server, null); serverReady = false; if (old is null) return;
        try { if (!old.HasExited) old.Kill(entireProcessTree: true); } catch (InvalidOperationException) { } catch (System.ComponentModel.Win32Exception) { } finally { old.Dispose(); }
    }
    public void Dispose()
    {
        if (disposed) return; disposed = true; lifetime.Cancel(); StopServer(); http.Dispose();
        if (IsInstalled) ContextualMemory.Save(memoryPath, new(memoryStamp, sentences.ToDictionary(), focuses.ToDictionary()));
    }
}
