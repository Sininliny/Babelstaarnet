using Babelstaarnet.Core;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace Babelstaarnet.Windows;

internal sealed class LanguagePackageState
{
    public bool Runtime { get; set; }
    public bool Conversion { get; set; }
    public string[] Models { get; set; } = [];
    public string[] Installed { get; set; } = [];
    public bool Ready(ReadingLanguagePair pair) => (pair.ConversionOnly || Runtime) && pair.ModelEdges.All(Models.Contains) && (!pair.NeedsConversion || Conversion);
    public string Description(ReadingLanguagePair pair) => string.Join(" · ", pair.ModelEdges.Select(e => e + (Models.Contains(e) ? " ready" : " missing"))) +
        (pair.NeedsConversion ? (pair.ModelEdges.Length > 0 ? " · " : "") + (Conversion ? "Script conversion ready" : "Script conversion missing") : "");
}
internal sealed class LanguagePackages : IDisposable
{
    private Process? process;
    public void Dispose() { try { if (process is { HasExited: false }) process.Kill(true); } catch (InvalidOperationException) { } }
    public async Task<LanguagePackageState> RunAsync(string operation, ReadingLanguagePair pair, ReadingLanguagePair active, Action<string> progress, CancellationToken token = default)
    {
        if (operation == "status" && !File.Exists(AppPaths.Python)) return new();
        string script = Path.Combine(AppContext.BaseDirectory, "LocalEngines", "language_support.py");
        var start = new ProcessStartInfo(operation == "install" ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe") : AppPaths.Python)
        { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true, StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8 };
        string[] args = operation == "install" ? ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", Path.Combine(AppContext.BaseDirectory, "LocalEngines", "install-language-support.ps1")]
            : ["-I", "-X", "utf8", "-u", script, operation];
        foreach (var arg in args) start.ArgumentList.Add(arg);
        foreach (var arg in operation == "install" ? new[] { "-DataDirectory", AppPaths.DataDirectory, "-Source", pair.Source.Id, "-Target", pair.Target.Id }
            : new[] { "--data-directory", AppPaths.DataDirectory, "--source", pair.Source.Id, "--target", pair.Target.Id, "--keep-source", active.Source.Id, "--keep-target", active.Target.Id }) start.ArgumentList.Add(arg);
        using var child = Process.Start(start) ?? throw new IOException("Language setup could not start."); process = child;
        Task<string> errors = child.StandardError.ReadToEndAsync(token); string? result = null;
        try
        {
            while (await child.StandardOutput.ReadLineAsync(token) is { } line)
            {
                if (line.Length > 64000) throw new IOException("Language setup returned an oversized response.");
                if (line.StartsWith('{'))
                {
                    using var doc = JsonDocument.Parse(line);
                    if (doc.RootElement.TryGetProperty("result", out var value)) result = value.GetRawText();
                    if (doc.RootElement.TryGetProperty("stage", out var stage)) progress(stage.GetString() ?? "Preparing…");
                }
            }
            await child.WaitForExitAsync(token); string details = await errors;
            if (child.ExitCode != 0) throw new IOException("Language setup failed. " + details[^Math.Min(1500, details.Length)..]);
            if (result is null) throw new IOException("Language setup returned no status.");
            return JsonSerializer.Deserialize<LanguagePackageState>(result, new JsonSerializerOptions { PropertyNameCaseInsensitive = true })!;
        }
        finally { process = null; if (!child.HasExited) child.Kill(true); }
    }
    public static bool ModelsAvailable(ReadingLanguagePair pair, string root)
    {
        try
        {
            var edges = new HashSet<string>();
            string path = Path.Combine(root, "Argos", "data", "argos-translate", "packages");
            if (Directory.Exists(path)) foreach (var metadata in Directory.EnumerateFiles(path, "metadata.json", SearchOption.AllDirectories))
            {
                using var document = JsonDocument.Parse(File.ReadAllText(metadata)); var model = document.RootElement;
                edges.Add(model.GetProperty("from_code").GetString() + "-" + model.GetProperty("to_code").GetString());
            }
            bool conversion = !pair.NeedsConversion || Directory.Exists(Path.Combine(root, "argos-venv", "Lib", "site-packages", "opencc"));
            return pair.ModelEdges.All(edges.Contains) && conversion;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException or KeyNotFoundException) { return false; }
    }
}
