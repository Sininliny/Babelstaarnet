namespace Babelstaarnet.Core;

public sealed class FeedbackMemory
{
    private readonly Dictionary<string, (bool Known, DateTimeOffset At)> actions = [];
    public bool? Recall(string word, DateTimeOffset now)
    {
        string key = ReadingPolicy.Key(word);
        if (!actions.TryGetValue(key, out var record)) return null;
        var age = now - record.At;
        if (age >= TimeSpan.Zero && age < TimeSpan.FromMinutes(5)) return record.Known;
        actions.Remove(key); return null;
    }
    public void Remember(string word, bool known, DateTimeOffset now)
    {
        foreach (string key in actions.Where(p => now - p.Value.At >= TimeSpan.FromMinutes(5)).Select(p => p.Key).ToArray()) actions.Remove(key);
        string identity = ReadingPolicy.Key(word);
        if (actions.Count >= 256 && !actions.ContainsKey(identity)) actions.Remove(actions.MinBy(p => p.Value.At).Key);
        actions[identity] = (known, now);
    }
}
