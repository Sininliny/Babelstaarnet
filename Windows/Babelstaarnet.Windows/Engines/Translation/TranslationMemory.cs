using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;

namespace Babelstaarnet.Windows;

// Only validated local model results are stored. A new bridge/model stamp
// invalidates the small cache; starting the Python worker is never required
// just to answer a word learned earlier in this installation.
internal static class TranslationMemory
{
    private sealed record Archive(string Stamp, Dictionary<string, string> Words);
    internal static Dictionary<string, string> Load(string path, string stamp)
    {
        try
        {
            if (!File.Exists(path) || new FileInfo(path).Length > 1_000_000) return [];
            var archive = JsonSerializer.Deserialize<Archive>(File.ReadAllText(path));
            if (archive?.Stamp != stamp || archive.Words is null || archive.Words.Count > 2048) return [];
            foreach (var pair in archive.Words) if (pair.Key.Length > 160 || pair.Value is null || pair.Value.Length > 1000) return [];
            return archive.Words;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException) { return []; }
    }
    internal static void Save(string path, string stamp, Dictionary<string, string> words)
    {
        string temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(temporary, JsonSerializer.Serialize(new Archive(stamp, words)));
            File.Move(temporary, path, overwrite: true);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        finally { try { File.Delete(temporary); } catch (IOException) { } catch (UnauthorizedAccessException) { } }
    }
}
