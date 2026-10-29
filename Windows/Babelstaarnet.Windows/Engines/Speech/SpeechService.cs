using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Windows.Media.Core;
using Windows.Media.Playback;
using Windows.Media.SpeechSynthesis;
using Windows.Storage.Streams;

namespace Babelstaarnet.Windows;

internal sealed class SpeechService : IDisposable
{
    private readonly SemaphoreSlim gate = new(1);
    private readonly Dictionary<string, byte[]> cache = [];
    private readonly bool muted;
    private readonly string sample;
    private ISpeechEngine engine;
    private CancellationTokenSource? utterance;
    private MediaPlayer? player;
    private MediaSource? source;
    private InMemoryRandomAccessStream? stream;
    private TaskCompletionSource? playback;
    private int generation;
    private bool disposed;
    internal int Syntheses { get; private set; }
    public string EngineId => engine.Id;
    public string EngineName => engine.DisplayName;
    public bool IsAvailable => engine.IsAvailable;

    public SpeechService(bool muted = false, ISpeechEngine? engine = null, string sample = "æbler")
    { this.sample = sample; this.muted = muted; this.engine = engine ?? new NeuralSpeechEngine(); }
    public static bool DanishAvailable => DanishVoice is not null;
    private static VoiceInformation? DanishVoice => Voice("da-DK");
    internal static bool Available(string locale) => Voice(locale) is not null;
    private static VoiceInformation? Voice(string locale) => SpeechSynthesizer.AllVoices
        .Where(v => v.Language.Replace('_', '-').Equals(locale, StringComparison.OrdinalIgnoreCase))
        .OrderBy(v => v.Id, StringComparer.Ordinal).FirstOrDefault();
    internal static async Task<SpeechSynthesisStream> SynthesizeAsync(string text, string locale = "da-DK")
    {
        using var synthesizer = new SpeechSynthesizer { Voice = Voice(locale) ??
            throw new InvalidOperationException($"No {locale} Windows voice is installed.") };
        return await synthesizer.SynthesizeTextToStreamAsync(text);
    }
    public void SelectEngine(ISpeechEngine next)
    {
        Stop(); engine.Dispose(); engine = next; cache.Clear();
    }
    public async Task WarmAsync()
    {
        if (!engine.IsAvailable) return;
        int before = generation;
        await AudioAsync(sample, CancellationToken.None);
        if (disposed || before != generation || player is not null) return;
        Task warm = SpeakCoreAsync(sample, silent: true);
        int request = generation;
        await warm;
        if (request == generation) Stop();
    }
    private async Task<byte[]> AudioAsync(string text, CancellationToken cancellationToken)
    {
        await gate.WaitAsync(cancellationToken);
        try
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            string key = engine.Id + "\n" + text;
            if (!cache.TryGetValue(key, out var audio))
            {
                audio = await engine.SynthesizeAsync(text, cancellationToken);
                cancellationToken.ThrowIfCancellationRequested();
                Syntheses++;
                if (cache.Count >= 24) cache.Remove(cache.Keys.First());
                cache[key] = audio;
            }
            return audio;
        }
        finally { gate.Release(); }
    }
    public Task SpeakAsync(string text) => SpeakCoreAsync(text, silent: false);
    private async Task SpeakCoreAsync(string text, bool silent)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        Stop(); int request = generation;
        using var cancellation = new CancellationTokenSource();
        utterance = cancellation;
        try
        {
            byte[] audio = await AudioAsync(text, cancellation.Token);
            if (request != generation || disposed) return;
            var next = new InMemoryRandomAccessStream();
            using (var writer = new DataWriter(next))
            {
                writer.WriteBytes(audio); await writer.StoreAsync(); writer.DetachStream();
            }
            if (request != generation || disposed) { next.Dispose(); return; }
            next.Seek(0); stream = next;
            if (player is null)
            {
                player = new MediaPlayer { AutoPlay = false, IsMuted = muted, RealTimePlayback = true, AudioCategory = MediaPlayerAudioCategory.Speech };
                player.PlaybackSession.PlaybackStateChanged += (_, _) =>
                { if (player?.PlaybackSession.PlaybackState == MediaPlaybackState.Playing) playback?.TrySetResult(); };
                player.MediaFailed += (_, e) => playback?.TrySetException(new InvalidOperationException("Speech could not play: " + e.ErrorMessage));
            }
            source = MediaSource.CreateFromStream(stream, "audio/wav");
            var started = playback = new(TaskCreationOptions.RunContinuationsAsynchronously);
            player.IsMuted = muted || silent; player.Source = source; player.Play();
            await started.Task.WaitAsync(TimeSpan.FromSeconds(5));
        }
        catch (OperationCanceledException) when (request != generation || disposed) { }
        finally { if (ReferenceEquals(utterance, cancellation)) utterance = null; }
    }
    public void Stop()
    {
        generation++; utterance?.Cancel(); utterance = null;
        playback?.TrySetCanceled(); playback = null;
        if (player is not null) { player.Pause(); player.Source = null; }
        source?.Dispose(); source = null; stream?.Dispose(); stream = null;
    }
    public void Dispose()
    {
        disposed = true; Stop(); engine.Dispose(); player?.Dispose(); player = null; cache.Clear();
    }
}
