# Babelstårnet on Windows

The native client supports Windows 10 version 2004 (build 19041) or newer and
Windows 11, on x64 PCs. It uses Windows OCR, Argos translation, local Piper
neural speech and optional Gemma 3 4B contextual meanings. Reading and speech
run offline. Screen pixels stay in memory.

## Install and set up

1. Extract the entire Windows ZIP and run `Babelstaarnet.exe`. Keep its adjacent
   files. Packages include the .NET runtime and are currently unsigned.
2. In **Windows Settings → Time & language → Language & region**, add Danish.
   Open its Language options and install **Optical character recognition**.
   Restart Babelstårnet afterwards. Windows' optional Text-to-speech feature
   is needed only for the basic Windows voice. Labels vary between OS versions.
3. Install 64-bit [Python 3.12](https://www.python.org/downloads/windows/).
   Choose **Settings → Local engines → Install / repair translation**.
   Setup creates a private environment, downloads Argos and its Danish → English
   model, then validates translation. It does not change your Python packages.
4. Choose **Settings → Translation → Install neural voice**. Setup installs
   Piper 1.8.0 separately and downloads `da_DK-talesyntese-medium` (about 63 MB),
   checking SHA-256. Speech then runs locally. Windows Danish is an explicit
   basic alternative; a missing neural voice never silently selects another
   language. **Voice** selects the engine; **Try voice** plays a sample.
5. Choose **Start translating** in the tray or press **Ctrl+Alt+Z**, then hover
   a Danish word. The first result appears independently of voice preparation.

Setup needs internet access. No runtime or model is embedded in the ZIP.
Click either mouse button on the tower tray logo to open controls, Word Book,
Settings and Quit. The tower is filled while active and adapts to taskbar
contrast. Hidden icons are available in the notification area's overflow.

## Windows appearance

Settings uses a resizable navigation window with one page at a time. Under
**Appearance**, choose the Windows setting, Light or Dark. Native windows use
the built-in Fluent theme; compact lookup cards, tray and book follow the same
palette and Windows accent. High contrast and reduced motion follow Windows
accessibility settings. Word Book recycles visible rows for large collections.
See [the design guide](WINDOWS_DESIGN.md) for the conventions.

## Reading controls

| Default | Action |
| --- | --- |
| Ctrl+Alt+Z | Start / pause reading |
| 1 | Mark the current word known |
| 2 | Mark unknown and save to Word Book |
| 3 | Pin / unpin and save the word |
| 4 | Show full sentence meaning / return to the bridge |
| Hold Alt | Keep the bubble while moving into its buttons |

**Settings → Shortcuts** records replacements and changes the hold modifier.
The toggle requires a modifier; duplicate shortcuts are rejected. Registration
conflicts preserve the previous working shortcut. Bubble shortcuts are active
only while a bubble is visible. Buttons remain available if a shortcut conflicts.

**Word meaning** and **Whole sentence** work independently. Both off leaves
speech-only reading. **Speak Danish on hover** defaults to on; **Speak after**
changes only pronunciation delay (0.45 seconds by default), not bubble timing.
The inline speaker replays the word. Refreshing a word does not repeat speech.
**Follow screen changes** off keeps one static snapshot per monitor; restart
reading to refresh. Power saving pauses scans after five seconds without input
and resumes on input. Holding and pinning also stop scans.

The overlay keeps compact reading geometry: a 280-point word panel with three
controls above a divider and a separate 420-point sentence panel. Both avoid
the source block. A rule underlines the actual word and its focused occurrence
in the reading line. Meanings use 16-point type, source words 12-point type.
Known feedback hides direct English; familiarity gradually fades Danish by
the same amount as Mac. Feedback confirmations survive revisiting for five
minutes. Adjacent English substitutions share a neutral tint.

The reader joins continuation lines in the same column and restores wrapped
hyphenated words. Danish abbreviations, dates, ordinals, URLs and quoted
punctuation follow the Mac sentence rules. Long sentences use a clause-bounded
window of at most 36 words around the pointed occurrence. Glossary tables,
beginner explanations and model prompts are generated from the Swift language
pack rather than maintained separately.

Word Book offers search, All/Learning/Known filters, speech, CSV export and
review in the same window. Right-click a row to speak, mark known or remove
from the book while preserving learning. In review, Space reveals, 1 records
Knew it, 2 records Didn't know, and Esc returns. Misses repeat once per sitting
and return after an hour. Remembered words progress through one, three, seven,
twenty-one and sixty days. Spaced encounters gradually remove English help;
repeated hovering in one sitting does not count as learning.

**What you have picked up** exports/imports Mac-compatible schema-1 learning
profiles and resets learning while preserving Word Book entries. Imports
validate the complete file, merge newest reviews and maximum counters, and
are idempotent. Learning identities preserve `æ`, `ø` and `å`. Legacy Windows
records migrate from their original spelling; first save preserves an untouched
`vocabulary.json.pre-unicode.bak`. Known dictionary forms transfer limited
familiarity to inflections; explicit unknown feedback overrides it.

## Optional offline contextual meanings

**Settings → Contextual meanings** uses the Gemma 3 4B model family and Danish
prompts used on Mac to select a word's meaning, dictionary form and beginner
explanation in its sentence. Install [Ollama for Windows](https://ollama.com/download/windows),
restart Babelstårnet, then choose **Install model**. Explicit setup downloads
about 3.3 GB. Existing local `gemma3:4b` weights are reused.

Reading starts an app-owned service on a random loopback port. Cloud is disabled
with `OLLAMA_NO_CLOUD=1`; the regular Ollama desktop app and updater are not
started. Only this owned service is stopped at exit. See
[Ollama's local-only and model-storage settings](https://docs.ollama.com/faq).
Requests remain on this PC. Only the explicit Install model action downloads.

A large model can take tens of seconds to load depending on hardware. Loading
runs in the background; ordinary meanings and Piper speech stay independent.
Focused meaning arrives before optional sentence enrichment. Bounded caches
reuse sentences. Stale answers are discarded; three failures disable context
until retry while ordinary translation continues. **Check model** retries.

## Data and troubleshooting

Data lives in `%LOCALAPPDATA%\Babelstaarnet` by default:

- `preferences.json`: voice, panel, delay, reading and shortcut settings.
- `vocabulary.json`: saved meanings, contexts and learning evidence;
  `vocabulary.json.lemmas.json` stores dictionary-form associations.
- `contextual-cache.json`: bounded local sentence meanings and focused
  explanations reused after restart, invalidated by model/prompt changes.
- `translation-cache.json`: up to 2,048 local translations reused after restart;
  changing the bridge or model installation invalidates it.
- `performance.json`: latest 64 numeric latency samples, without recognized
  text or pixels. Settled-to-card/meaning samples include app scheduling.
- `argos-venv` and `Argos`: private translation runtime, model and cache.
- `piper-venv` and `Piper`: private speech runtime and Danish model.
- `Contextual/models`: optional model downloads, unless existing local weights
  are reused from Ollama's model directory.

Set `BABELSTAARNET_DATA_DIRECTORY` to an absolute path before launch for an
isolated or portable data folder. Setup and reading both use it.

Repair translation through Settings if a worker fails or a model is missing.
Requests have a sixty-second deadline. A canceled hover stops waiting promptly,
but its in-flight reply is drained and cached without restarting the worker.
Only failure, deadline or exit discards it. Word translation loads the model
and tokenizer directly without unused sentence-processing libraries.

If Python is not found, specify it explicitly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Scripts\install-local-engines.ps1 -PythonPath 'C:\Path To Python\python.exe'
```

In a downloaded package, use `LocalEngines\install-local-engines.ps1` instead.

OCR reads visible text and images near the pointer. Secure desktops, protected
video and apps that prohibit capture cannot be read. Physical pixel coordinates
support negative monitor origins and mixed scaling. The bubble is excluded only
during the app's own pixel copy. Pin it before opening a screenshot tool to
keep pointer movement from dismissing it.

Capture adapts to text size, starting at 620 × 250 logical pixels. Fresh pixels
validate cached positions; unchanged text avoids OCR. New words scan after
35 ms of settled input, separately from the 600 ms refresh. Misses retry after
150 ms. Optional gloss work yields after batches of at most four words. Pixel
comparison reads native rows directly without copying an unchanged image.
Compositor waits, screenshot copies, OCR preprocessing and encounter serialization
run away from the UI thread. Unchanged sentence tokens and native frames are
reused. Pause/resume retains the loaded translation, OCR, voice and audio cache.

Platform differences remain: Apple Vision, Apple dictionary resources, Apple
fonts and glass are unavailable on Windows. Windows OCR, Segoe UI typography
and a neutral rounded material take their place; recognition and generated
wording can differ. Local storage is separate; profiles transfer learning.

Speech implements `ISpeechEngine`; future offline engines can replace Piper
without changing hover or playback logic. See the
[Danish model card](https://huggingface.co/rhasspy/piper-voices/blob/main/da/da_DK/talesyntese/medium/MODEL_CARD)
and [Piper runtime](https://github.com/OHF-Voice/piper1-gpl) for attribution.

## Build and check

Install .NET 10 SDK and Python 3. No Swift, Xcode, shell emulation or third-party
.NET UI package is required. The first build restores Windows SDK references.
From the repository root in PowerShell (including Windows PowerShell 5.1):

```powershell
dotnet run --project .\Windows\Babelstaarnet.Windows
.\Scripts\test-windows.ps1
.\Scripts\build-windows.ps1
.\Scripts\package-windows.ps1
```

Publishing creates a self-contained x64 app in `dist\Babelstaarnet-Windows-x64`.
Packaging adds a ZIP and SHA-256 checksum. Models install per user separately.
Tests cover geometry, sentence boundaries, repeated word focus, Danish data,
learning migration, lemma transfer, review, profiles, settings callbacks,
native shortcut rollback, icons, worker concurrency/cancellation/failure and
native window lifecycles. The language sync script's `--check` detects drift
from Swift. Real OCR/speech checks report skips if prerequisites are absent.
Audio playback checks are muted.

Set `BABELSTAARNET_TEST_PYTHON` to an interpreter if autodetection fails.
Set `BABELSTAARNET_ARGOS_TEST_DATA` to an installed data folder to exercise
real Argos (including 32 word comparisons) and the real Piper model.
Additional compiled `WindowsChecks.exe` modes:

- `--window-lifecycle`: tray-to-Settings/Word Book regression on invisible,
  nonactivating windows, including deactivation during close and repeated close.
- `--context-check`: real installed local Gemma, two meanings of `får`, dictionary
  forms, Danish explanation and cache reuse; downloads nothing.
- `--benchmark <output.json>`: cold/warm translation, cancellation and OCR timing;
  persistent translation memory is disabled for comparable raw timings.
- `--hover-benchmark <output.json>`: fixture OCR → production hover session →
  WPF rendering and muted playback. Includes settle delay, excludes desktop
  capture and OS pointer events; real hover testing remains useful.
- `--render-ui <output.png>`: production word/sentence panels in normal, known
  and loading states, tray, settings, book, review and icon variants. Does not
  open a desktop window.

Microsoft references: [Windows OCR](https://learn.microsoft.com/en-us/uwp/api/windows.media.ocr.ocrengine),
[desktop Windows Runtime APIs](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/winrt-apis-desktop-apps).

## Optional DR news

**Word Book → Read something new** offers DR's public RSS headlines and excerpts.
It is off by default and explicitly labelled as an internet feature. Topic choice,
recent learning matches and seen stories stay on this PC; requests do not contain
your vocabulary or screen content. DR still sees ordinary connection information.
**Read original** opens your browser. **Simplify excerpt · local AI** uses an already
installed contextual model, shows the original alongside it, and pauses for reading.

Enable background refresh and daily digests separately under **Settings → News
(internet)**. Digests work while the app runs, at most once daily, outside reading
and quiet hours. Turning news off turns both options off. Cached content remains
available; an unavailable feed never blocks offline translation or speech.

Source builds require CMake and Visual Studio C++ build tools in addition to .NET
10 and Python. The build includes `babel_policy.dll`, the same native learning and
news rules statically compiled into the Mac client. End users need neither CMake
nor Visual Studio. See [cross-platform development](DEVELOPMENT.md).
