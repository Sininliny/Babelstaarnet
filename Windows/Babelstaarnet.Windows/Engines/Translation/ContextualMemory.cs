using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;

namespace Babelstaarnet.Windows;

internal static class ContextualMemory
{
    internal sealed record Archive(string Stamp, Dictionary<string, Dictionary<string, string>> Sentences, Dictionary<string, FocusedGloss> Focuses);
    internal static Archive Load(string path, string stamp)
    {
        try
        {
            if (!File.Exists(path) || new FileInfo(path).Length > 2_000_000) return new(stamp, [], []);
            var data = JsonSerializer.Deserialize<Archive>(File.ReadAllText(path));
            if (data?.Stamp != stamp || data.Sentences is null || data.Focuses is null || data.Sentences.Count > 256 || data.Focuses.Count > 1024) return new(stamp, [], []);
            if (data.Sentences.Any(p => p.Key.Length > 4000 || p.Value is null || p.Value.Count > 36 || p.Value.Any(g => g.Key.Length > 100 || g.Value is null || g.Value.Length > 120)) ||
                data.Focuses.Any(p => p.Key.Length > 4100 || p.Value is null || p.Value.Meaning is null || p.Value.Meaning.Length > 120 || p.Value.Lemma is null || p.Value.Lemma.Length > 40 || p.Value.Explanation is null || p.Value.Explanation.Length > 800)) return new(stamp, [], []);
            return data;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException) { return new(stamp, [], []); }
    }
    internal static void Save(string path, Archive archive)
    {
        string temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            string json = JsonSerializer.Serialize(archive);
            if (System.Text.Encoding.UTF8.GetByteCount(json) > 2_000_000) return;
            Directory.CreateDirectory(Path.GetDirectoryName(path)!); File.WriteAllText(temporary, json); File.Move(temporary, path, overwrite: true);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        finally { try { File.Delete(temporary); } catch (IOException) { } catch (UnauthorizedAccessException) { } }
    }
}
