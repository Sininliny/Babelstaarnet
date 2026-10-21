using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace Babelstaarnet.Windows;

internal sealed class NeuralSpeechEngine : ISpeechEngine
{
    private readonly string data;
    private readonly string bridge;
    private readonly SemaphoreSlim gate = new(1);
    private readonly CancellationTokenSource lifetime = new();
    private readonly object sync = new();
    private Process? worker;
    private string errors = "";
    private bool disposed;
    internal int WorkerStarts { get; private set; }
    public string Id => "piper:da_DK-talesyntese-medium:1";
    public string DisplayName => "Danish neural · talesyntese (offline)";
    private string Python => Path.Combine(data, "piper-venv", "Scripts", "python.exe");
    private string ModelDirectory => Path.Combine(data, "Piper", "da_DK-talesyntese-medium");
    public bool IsAvailable => File.Exists(Python) && File.Exists(bridge) &&
        File.Exists(Path.Combine(ModelDirectory, "da_DK-talesyntese-medium.onnx")) &&
        File.Exists(Path.Combine(ModelDirectory, "da_DK-talesyntese-medium.onnx.json"));
    public NeuralSpeechEngine(string? data = null, string? bridge = null)
    { this.data = data ?? AppPaths.DataDirectory; this.bridge = bridge ?? AppPaths.SpeechBridge; }

    public async Task<byte[]> SynthesizeAsync(string text, CancellationToken cancellationToken)
    {
        Task<byte[]> operation = SynthesizeCoreAsync(text, cancellationToken);
        try { return await operation.WaitAsync(cancellationToken).ConfigureAwait(false); }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        { _ = DrainAsync(operation); throw; }
    }
    private static async Task DrainAsync(Task operation) { try { await operation.ConfigureAwait(false); } catch { } }
    private async Task<byte[]> SynthesizeCoreAsync(string text, CancellationToken waiting)
    {
        await gate.WaitAsync(waiting).ConfigureAwait(false);
        try
        {
            waiting.ThrowIfCancellationRequested();
            var process = GetWorker();
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
            timeout.CancelAfter(TimeSpan.FromSeconds(30));
            try
            {
                string request = JsonSerializer.Serialize(new { text });
                await process.StandardInput.WriteLineAsync(request.AsMemory(), timeout.Token).ConfigureAwait(false);
                await process.StandardInput.FlushAsync(timeout.Token).ConfigureAwait(false);
                string line = await process.StandardOutput.ReadLineAsync(timeout.Token).ConfigureAwait(false) ??
                    throw new IOException("The Danish neural voice stopped. " + LastError());
                if (line.Length > 4_000_000) throw new IOException("The voice returned oversized audio.");
                using var reply = JsonDocument.Parse(line);
                if (reply.RootElement.GetProperty("language").GetString() != "da-DK") throw new IOException("The neural voice is not Danish.");
                byte[] wav = Convert.FromBase64String(reply.RootElement.GetProperty("audio").GetString()!);
                if (wav.Length < 44 || !wav.AsSpan(0, 4).SequenceEqual("RIFF"u8)) throw new IOException("The neural voice returned invalid audio.");
                return wav;
            }
            catch (OperationCanceledException) when (!lifetime.IsCancellationRequested)
            { StopWorker(); throw new TimeoutException("The local Danish voice did not respond within 30 seconds."); }
            catch { StopWorker(); throw; }
        }
        finally { gate.Release(); }
    }
    private Process GetWorker()
    {
        lock (sync)
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            if (worker is not null && !worker.HasExited) return worker;
            if (!IsAvailable) throw new FileNotFoundException("Install the offline Danish neural voice in Settings → Translation.");
            StopWorker();
            var start = new ProcessStartInfo(Python)
            {
                UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true,
                StandardInputEncoding = new UTF8Encoding(false), StandardOutputEncoding = Encoding.UTF8,
                StandardErrorEncoding = Encoding.UTF8, WorkingDirectory = data
            };
            foreach (string arg in new[] { "-I", "-X", "utf8", "-u", bridge, "--model-directory", ModelDirectory }) start.ArgumentList.Add(arg);
            start.Environment["OMP_NUM_THREADS"] = "2";
            errors = "";
            worker = new Process { StartInfo = start };
            worker.ErrorDataReceived += (_, e) => { if (e.Data is null) return; lock (sync) { errors += e.Data + "\n"; errors = errors[^Math.Min(errors.Length, 2000)..]; } };
            worker.Start(); WorkerStarts++; worker.BeginErrorReadLine();
            return worker;
        }
    }
    private string LastError() { lock (sync) return errors.Trim(); }
    private void StopWorker()
    {
        Process? old;
        lock (sync) { old = worker; worker = null; }
        if (old is null) return;
        try { if (!old.HasExited) old.Kill(entireProcessTree: true); }
        catch (InvalidOperationException) { }
        finally { old.Dispose(); }
    }
    public void Dispose() { lock (sync) { disposed = true; lifetime.Cancel(); } StopWorker(); }
}
