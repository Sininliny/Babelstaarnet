namespace Babelstaarnet.Core;

public sealed record BridgeToken(string Text, bool English, bool Focus = false, int KnowledgeLevel = 0);
public static class BridgePresentation
{
    public static IReadOnlyList<BridgeToken> Tokens(HoveredText hit, IReadOnlyDictionary<string, string> glosses, Func<string, bool> known, Func<string, int>? level = null)
    {
        hit = SentenceWindow.Around(hit);
        var matches = ReadingPolicy.Words().Matches(hit.Line.Text);
        var tokens = new List<BridgeToken>();
        int occurrence = 0;
        for (int i = 0; i < matches.Count; i++)
        {
            var match = matches[i];
            string key = ReadingPolicy.Key(match.Value);
            bool english = !known(key) && ReadingPolicy.TryGloss(glosses, key, out var gloss) && !string.IsNullOrWhiteSpace(gloss) && ReadingPolicy.Key(gloss) != key;
            string value = english ? DanishLanguage.Display(string.Join(' ', ReadingPolicy.TryGloss(glosses, key, out var answer) ? answer.Split(' ').Take(4) : [])) : match.Value;
            if (english && value.Length > 0)
            {
                if (i == 0 && char.IsUpper(match.Value[0]) && char.IsLower(value[0])) value = char.ToUpperInvariant(value[0]) + value[1..];
                else if (i > 0 && char.IsLower(match.Value[0]) && char.IsUpper(value[0])) value = char.ToLowerInvariant(value[0]) + value[1..];
            }
            string prefix = i == 0 ? hit.Line.Text[..match.Index].Trim() : "";
            int next = i + 1 < matches.Count ? matches[i + 1].Index : hit.Line.Text.Length;
            string suffix = hit.Line.Text[(match.Index + match.Length)..next].Trim();
            bool focus = key == ReadingPolicy.Key(hit.Word.Text) && occurrence++ == hit.FocusOccurrence;
            tokens.Add(new(DanishLanguage.Display(prefix + value + suffix), english, focus, level?.Invoke(key) ?? 0));
        }
        return tokens;
    }
}
