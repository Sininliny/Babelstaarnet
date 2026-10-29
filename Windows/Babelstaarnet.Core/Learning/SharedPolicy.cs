using System;
using System.Runtime.InteropServices;

namespace Babelstaarnet.Core;

// Only marshaling lives here; the rules are compiled from Shared/BabelPolicy.
public static class SharedPolicy
{
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)] public static extern int bp_news_popup_due(int enabled, int background, int optedIn, int blocked, int hour, double elapsed, int interval, int shown, int fresh);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)] public static extern int bp_news_gloss(int level, int available, int different);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)] public static extern int bp_news_reader_band(int knownBasic, int basicTotal, int knownEveryday, int everydayTotal);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)] public static extern int bp_news_target_budget(int wordCount);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)] public static extern int bp_news_word_mode(int level, int wordBand, int readerBand, int helpReady, int targetsUsed, int targetBudget);
    private const string Library = "babel_policy";
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)] public static extern int bp_version();
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)] public static extern int bp_reading_help(int requested, int english, int cached, int available);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)] public static extern int bp_retry_delay(int failures);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)] public static extern int bp_source_capability(int capability);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)] public static extern int bp_target_allowed(int count, int already);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)] public static extern int bp_anchor(int level, int supported, int focus, int newSense, int cooldown, int selected);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)] public static extern int bp_challenge(int supported, int reliable, int learned, int newSense, int helps, int used);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)] public static extern int bp_evidence(int kind, int correct, int hinted);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)] public static extern int bp_fetch(int enabled, int background, int requestBackground, int manual, double attempt, double success);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)] public static extern int bp_digest(int enabled, int background, int notify, int permitted, int reading, int quiet, int sent, int fresh);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)] public static extern int bp_rewrite(int allows, int text, int model, int reading, int preempt);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)] public static extern double bp_news_score(double age, double interest, double matches, double readability, int seen);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)] private static extern int bp_contains([MarshalAs(UnmanagedType.LPUTF8Str)] string text, [MarshalAs(UnmanagedType.LPUTF8Str)] string unit);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)] private static extern int bp_same_story([MarshalAs(UnmanagedType.LPUTF8Str)] string a, [MarshalAs(UnmanagedType.LPUTF8Str)] string b);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)] private static extern IntPtr bp_feed_url(int topic);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)] private static extern IntPtr bp_rewrite_prompt();
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)] private static extern int bp_summary_valid([MarshalAs(UnmanagedType.LPUTF8Str)] string source, [MarshalAs(UnmanagedType.LPUTF8Str)] string summary, [MarshalAs(UnmanagedType.LPUTF8Str)] string markers);
    public static bool SummaryValid(string source, string summary, string[]? markers = null) => !source.Contains('\0') && !summary.Contains('\0') && bp_summary_valid(source.Normalize(), summary.Normalize(), string.Join('\n', markers ?? [])) != 0;
    public static bool Contains(string text, string unit) => bp_contains(text.Normalize().ToLowerInvariant(), unit.Normalize().ToLowerInvariant()) != 0;
    public static bool SameStory(string a, string b) => bp_same_story(a.Normalize().ToLowerInvariant(), b.Normalize().ToLowerInvariant()) != 0 && bp_same_story(b.Normalize().ToLowerInvariant(), a.Normalize().ToLowerInvariant()) != 0;
    public static string FeedUrl(int topic) => Marshal.PtrToStringUTF8(bp_feed_url(topic))!;
    public static string RewritePrompt => Marshal.PtrToStringUTF8(bp_rewrite_prompt())!;
}
