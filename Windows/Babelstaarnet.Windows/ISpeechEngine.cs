using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;

namespace Babelstaarnet.Windows;

// Engines produce Danish WAV bytes. Selection, hover cancellation, caching
// and playback stay independent of the model so another local engine can be
// added without changing the reader or overlay.
internal interface ISpeechEngine : IDisposable
{
    string Id { get; }
    string DisplayName { get; }
    bool IsAvailable { get; }
    Task<byte[]> SynthesizeAsync(string text, CancellationToken cancellationToken);
}

internal sealed class WindowsDanishEngine : ISpeechEngine
{
    public string Id => "windows:da-DK";
    public string DisplayName => "Windows Danish (basic)";
    public bool IsAvailable => SpeechService.DanishAvailable;
    public async Task<byte[]> SynthesizeAsync(string text, CancellationToken cancellationToken)
    {
        using var audio = await SpeechService.SynthesizeAsync(text);
        using var input = audio.AsStreamForRead();
        using var output = new MemoryStream();
        await input.CopyToAsync(output, cancellationToken);
        return output.ToArray();
    }
    public void Dispose() { }
}
