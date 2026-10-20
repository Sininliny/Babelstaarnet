using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Threading.Tasks;

namespace Babelstaarnet.Windows;

// Bounded numeric timings, never screenshots or recognized text. Saving is
// debounced off the UI thread so diagnostics cannot hold up a hover.
internal sealed class LatencyLog
{
    private readonly string path;
    private readonly object sync = new();
    private readonly Queue<object> samples = [];
    private bool saving;
    internal LatencyLog(string path) => this.path = path;
    internal void Record(string stage, double milliseconds)
    {
        lock (sync)
        {
            if (samples.Count == 64) samples.Dequeue();
            samples.Enqueue(new { stage, ms = Math.Round(milliseconds, 1), utc = DateTimeOffset.UtcNow });
            if (saving) return;
            saving = true;
        }
        _ = SaveAsync();
    }
    private async Task SaveAsync()
    {
        await Task.Delay(1000).ConfigureAwait(false);
        object[] recent;
        lock (sync) { recent = samples.ToArray(); saving = false; }
        try
        {
            string json = JsonSerializer.Serialize(new { build = "windows-preview-4", samples = recent }, new JsonSerializerOptions { WriteIndented = true });
            await Task.Run(() => { Directory.CreateDirectory(Path.GetDirectoryName(path)!); File.WriteAllText(path, json); }).ConfigureAwait(false);
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }
}
