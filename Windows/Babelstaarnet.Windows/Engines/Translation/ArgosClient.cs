using Babelstaarnet.Core;
using System;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace Babelstaarnet.Windows;

// The same newline-delimited JSON worker used by the Swift client. One request
// owns the pipe at a time. Canceling a hover stops waiting for its result, but
// the bounded background request still drains its reply and warms the cache.
// Only worker failure, its own deadline, or app shutdown discards the process.
internal sealed class ArgosClient : IDisposable
{
    private readonly string python;
    private readonly string bridge;
    private readonly string dataDirectory;
    private readonly SemaphoreSlim gate = new(1);
    private readonly ConcurrentDictionary<string, string> cache = new(StringComparer.Ordinal);
    private readonly CancellationTokenSource lifetime = new();
    private readonly object workerLock = new();
    private readonly TimeSpan requestTimeout;
    private Process? worker;
    private readonly object errorLock = new();
    private string errors = "";
    private bool disposed;
    private readonly string memoryPath, memoryStamp;
    private readonly bool persistentMemory;
    private readonly ReadingLanguagePair languages;
    private readonly bool verifyPackages;

    public ArgosClient(string? python = null, string? bridge = null, string? dataDirectory = null,
        TimeSpan? requestTimeout = null, bool persistentMemory = true, ReadingLanguagePair? languages = null, bool verifyPackages = false)
    {
        this.languages = languages ?? LanguageCatalog.Pair();
        this.verifyPackages = verifyPackages;
        this.python = python ?? AppPaths.Python;
        this.bridge = bridge ?? AppPaths.Bridge;
        this.dataDirectory = dataDirectory ?? AppPaths.DataDirectory;
        this.requestTimeout = requestTimeout ?? TimeSpan.FromSeconds(60);
        this.persistentMemory = persistentMemory;
        memoryPath = Path.Combine(this.languages.ProfileDirectory(this.dataDirectory), "translation-cache.json");
        string packages = Path.Combine(this.dataDirectory, "Argos", "data", "argos-translate", "packages");
        memoryStamp = this.languages.Id + "|" + this.python + "|" + this.bridge + "|" + File.GetLastWriteTimeUtc(this.bridge).Ticks + "|" + Directory.GetLastWriteTimeUtc(packages).Ticks;
        if (persistentMemory) foreach (var pair in TranslationMemory.Load(memoryPath, memoryStamp)) cache[pair.Key] = pair.Value;
    }

    public bool IsInstalled => File.Exists(python) && File.Exists(bridge) && (!verifyPackages || LanguagePackages.ModelsAvailable(languages, dataDirectory));
    internal void ReleaseModels() => StopWorker();
    internal int WorkerStarts { get; private set; }

    public Task<IReadOnlyList<string>> TranslateAsync(IReadOnlyList<string> texts,
        CancellationToken cancellationToken) => RunAsync(texts.ToArray(), cancellationToken, false);

    public async Task WarmAsync(CancellationToken cancellationToken) =>
        await RunAsync([languages.Source.Sample], cancellationToken, true).ConfigureAwait(false);

    public bool TryGetCached(string text, out string translation) => cache.TryGetValue(text, out translation!);

    private async Task<IReadOnlyList<string>> RunAsync(string[] texts, CancellationToken cancellationToken, bool warmup)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        cancellationToken.ThrowIfCancellationRequested();
        if (!warmup)
        {
            var available = new string[texts.Length]; bool complete = true;
            for (int i = 0; i < texts.Length; i++) if (!cache.TryGetValue(texts[i], out available[i]!)) { complete = false; break; }
            if (complete) return available;
        }
        Task<IReadOnlyList<string>> operation = TranslateCoreAsync(texts, cancellationToken, warmup);
        try { return await operation.WaitAsync(cancellationToken).ConfigureAwait(false); }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            _ = ObserveCompletionAsync(operation);
            throw;
        }
    }

    private static async Task ObserveCompletionAsync(Task operation)
    {
        try { await operation.ConfigureAwait(false); }
        catch { /* The abandoned hover has no UI; the next request can retry. */ }
    }

    private async Task<IReadOnlyList<string>> TranslateCoreAsync(string[] texts, CancellationToken waitingToken, bool warmup)
    {
        await gate.WaitAsync(waitingToken).ConfigureAwait(false);
        try
        {
            // Queued stale hovers never reach the pipe. Once sent, the reply
            // belongs to this operation until it is drained or times out.
            waitingToken.ThrowIfCancellationRequested();
            return await TranslateOwnedAsync(texts, warmup).ConfigureAwait(false);
        }
        finally { gate.Release(); }
    }

    private async Task<IReadOnlyList<string>> TranslateOwnedAsync(string[] texts, bool warmup)
    {
        try
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            var results = new Dictionary<string, string>(StringComparer.Ordinal);
            foreach (string text in texts)
                if (cache.TryGetValue(text, out string? cached)) results[text] = cached;
            var missing = texts.Distinct(StringComparer.Ordinal).Where(t => !results.ContainsKey(t)).ToArray();
            if (missing.Length > 0 || warmup)
            {
                Process process = GetWorker();
                using var timeout = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
                timeout.CancelAfter(requestTimeout);
                string request = JsonSerializer.Serialize(new { texts = missing });
                await process.StandardInput.WriteLineAsync(request.AsMemory(), timeout.Token).ConfigureAwait(false);
                await process.StandardInput.FlushAsync(timeout.Token).ConfigureAwait(false);
                string? line = await process.StandardOutput.ReadLineAsync(timeout.Token).ConfigureAwait(false);
                if (line is null) throw new IOException("The offline translator stopped. " + LastError());
                if (line.Length > 64_000) throw new IOException("The offline translator returned an oversized response.");
                using var response = JsonDocument.Parse(line);
                string[] translations = response.RootElement.GetProperty("translations").EnumerateArray()
                    .Select(e => e.GetString() ?? "").ToArray();
                if (translations.Length != missing.Length)
                    throw new IOException("The offline translator returned an incomplete response.");
                for (int i = 0; i < missing.Length; i++) results[missing[i]] = translations[i];
                if (cache.Count + missing.Length > 2048)
                {
                    cache.Clear();
                    foreach (var pair in results.TakeLast(2048)) cache[pair.Key] = pair.Value;
                }
                else for (int i = 0; i < missing.Length; i++) cache[missing[i]] = translations[i];
            }
            return texts.Select(t => results[t]).ToArray();
        }
        catch (OperationCanceledException) when (!lifetime.IsCancellationRequested)
        {
            StopWorker();
            throw new TimeoutException($"The offline translator took longer than {requestTimeout.TotalSeconds:0.#} seconds. Try starting again, or repair translation in Settings → Local engines.");
        }
        catch
        {
            StopWorker();
            throw;
        }
    }

    private Process GetWorker()
    {
        lock (workerLock)
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            if (worker is null || worker.HasExited) StartWorker();
            return worker!;
        }
    }

    // Called under workerLock so shutdown cannot race a newly started process.
    private void StartWorker()
    {
        StopWorker();
        if (!IsInstalled) throw new FileNotFoundException("Set up offline translation from the tray menu first.");
        var start = new ProcessStartInfo(python)
        {
            UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true,
            StandardInputEncoding = new UTF8Encoding(false), StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8, WorkingDirectory = dataDirectory
        };
        foreach (string argument in new[] { "-I", "-X", "utf8", "-u", bridge, "--word-server", "--source", languages.Source.Id, "--target", languages.Target.Id })
            start.ArgumentList.Add(argument);
        foreach (string kind in new[] { "data", "config", "cache" })
        {
            string directory = Path.Combine(dataDirectory, "Argos", kind);
            Directory.CreateDirectory(directory);
            start.Environment["XDG_" + kind.ToUpperInvariant() + "_HOME"] = directory;
        }
        start.Environment["ARGOS_CHUNK_TYPE"] = "MINISBD";
        start.Environment["ARGOS_DEVICE_TYPE"] = "cpu";
        start.Environment["ARGOS_MODEL_PROVIDER"] = "OPENNMT";
        start.Environment["ARGOS_PACKAGES_DIR"] = Path.Combine(dataDirectory, "Argos", "data", "argos-translate", "packages");
        start.Environment["ARGOS_INTER_THREADS"] = "1";
        start.Environment["ARGOS_INTRA_THREADS"] = "2";
        lock (errorLock) errors = "";
        worker = new Process { StartInfo = start };
        worker.ErrorDataReceived += (_, e) =>
        {
            if (e.Data is null) return;
            lock (errorLock)
            {
                errors += e.Data + "\n";
                if (errors.Length > 2048) errors = errors[^2048..];
            }
        };
        worker.Start();
        WorkerStarts++;
        worker.BeginErrorReadLine();
    }

    private string LastError() { lock (errorLock) return errors.Trim(); }

    private void StopWorker()
    {
        Process? old;
        lock (workerLock) { old = worker; worker = null; }
        if (old is null) return;
        try { if (!old.HasExited) old.Kill(entireProcessTree: true); }
        catch (InvalidOperationException) { }
        finally { old.Dispose(); }
    }

    public void Dispose()
    {
        lock (workerLock) { if (disposed) return; disposed = true; }
        lifetime.Cancel();
        StopWorker();
        if (persistentMemory) TranslationMemory.Save(memoryPath, memoryStamp, cache.Where(p => p.Key.Length <= 160 && p.Value.Length <= 1000).Take(2048).ToDictionary());
    }
}
