# Cross-platform development

Both native apps provide Danish reading support. Their reading rules and data
formats should agree; their window systems and visual conventions can differ.
The native platform supplies OCR, screen capture, speech playback, shortcuts
and window integration. There is no web frontend or shared UI runtime.

Learning behavior and opt-in online news are specified in the
[learning decision policy](LEARNING_POLICY.md), with
[design acceptance cases](learning-policy-cases.json). Runtime vectors in
`Tests/Shared/policy-runtime.json` exercise the actual shared native component.
See [the shared-policy decision](ADR-001-SHARED-POLICY.md) for the ABI and boundaries.

## Repository map

| Location | Responsibility |
| --- | --- |
| `Sources/BabelCore` | Swift reading primitives and language contracts |
| `Shared/BabelPolicy` | One C11 implementation of learning and news decisions, compiled by both clients |
| `Sources/BabelNews` | Mac public-feed, cache and notification scheduling adapter |
| `Sources/LanguageDanish` | Canonical Danish tables, prompts and rules |
| `Sources/BabelOCR`, `BabelTranslate`, `BabelLexicon`, `BabelSpeech` | Mac capability adapters |
| `Sources/BabelstaarnetKit`, `Babelstaarnet` | Mac application and SwiftUI presentation |
| `Windows/Babelstaarnet.Core/Reading`, `Learning`, `Language`, `Shortcuts` | Domain behavior without WPF or Win32 |
| `Windows/Babelstaarnet.Windows/App` | Composition, preferences and lifecycle |
| `Windows/Babelstaarnet.Windows/Engines` | Translation, contextual model and speech adapters |
| `Windows/Babelstaarnet.Windows/Platform` | Native OCR/capture, pixel snapshots, icons and hotkeys |
| `Windows/Babelstaarnet.Windows/Presentation` | Controls, theme, overlay, settings, tray and Word Book |
| `Windows/Babelstaarnet.Windows/Diagnostics` | Bounded numeric latency recording |
| `Resources/LocalEngines` | Local Python worker protocols; downloads only through setup |
| `Resources/LanguagePacks` | Generated Windows language data |
| `Tests/Shared` | Behavior examples consumed by both native test programs |
| `Tests/BabelstaarnetTests`, `Tests/WindowsChecks` | Native checks and fixture renderers |
| `Scripts` | Stable build, install, test and packaging entry points |

Keep platform-specific APIs in the adapters and presentation projects. The
Windows domain project must remain free of WPF, Win32 and application references.
Its folder names describe responsibilities; namespaces remain stable. The
root `.slnx` opens all .NET projects together. `global.json` selects .NET 10
with feature-band roll-forward. `.editorconfig` and `.gitattributes` keep source
encoding and line endings predictable on both systems.

## Shared behavior

`Sources/LanguageDanish/Danish.swift` owns Danish glossary tables, beginner
explanations, abbreviation rules and model prompts. After changing them, run:

```text
python Scripts/sync-windows-language.py
python Scripts/check-repository.py
```

The second command checks generated data, project references, native version
agreement and basic platform boundaries without downloading anything.
`Resources/Info.plist` and the Windows application version must agree; the
checker catches accidental divergence.

`Tests/Shared/reading-contract.json` is a set of examples, not another copy of
the implementation. The Swift `CrossPlatformContractChecks` and C#
`NativeExperienceChecks` execute it against their actual domain functions.
Add examples here when a bug could recur on either platform. Native tests
also cover geometry, learning/profile merge, review and cancellation.

Learning profiles use the same schema-1 archive on both systems. Platform
preferences, model runtimes and local caches stay separate. Moving code must
never move a user's vocabulary or invalidate their learning profile.

## Commands

| Task | Windows / PowerShell | macOS |
| --- | --- | --- |
| Repository contracts | `python Scripts/check-repository.py` | `python3 Scripts/check-repository.py` |
| Build | `dotnet build Babelstaarnet.slnx` | `make build` |
| Native checks | `./Scripts/test-windows.ps1` | `make test` |
| App | `./Scripts/build-windows.ps1` | `make app` |
| Package | `./Scripts/package-windows.ps1` | `make release` |

Windows requires .NET 10 SDK, CMake, Visual Studio C++ build tools and Python 3 for worker tests. Mac requires the
Swift/Xcode toolchain described in the README. CI runs both native jobs on
`main`, `codex/**` branches and pull requests. Packaging checks use clean
outputs; downloaded runtimes and model weights do not enter release archives.

Windows checks fail UI callback errors instead of opening blocking dialogs.
Window lifecycle fixtures are invisible and nonactivating. Do not operate an
unrelated desktop application as part of automated verification.

## Performance work

Use the release `WindowsChecks.exe` modes documented in [the Windows guide](WINDOWS.md).
For real installed engines, set `BABELSTAARNET_ARGOS_TEST_DATA` and
`BABELSTAARNET_DATA_DIRECTORY` to an existing isolated data folder. Tests do
not install missing engines. Audio checks are muted.

- `--benchmark <file.json>` measures cold/warm translation, OCR and allocation.
  Persistent word memory is disabled for raw translation comparisons.
- `--hover-benchmark <file.json>` includes fixture OCR, production session,
  actual WPF rendering and muted playback. It excludes desktop capture and OS
  pointer scheduling. Report that limit with the numbers.
- `--render-ui <file.png>` renders production surfaces in both light and dark
  modes, including the Windows settings shell and Word Book.
- `--context-check` exercises the existing local model, word-only requests,
  familiar-word filtering and contextual cache reuse across restart.

Measure before and after on the same machine without concurrent builds or
inference jobs. Separate warm cache measurements from cold initialization.
Prefer allocation/realization budgets over fragile millisecond assertions in
CI. Current checks bound unchanged 4K pixel comparison allocations and the
number of realized rows in a 5,000-entry Word Book.

Runtime diagnostics contain numeric timings rather than recognized text.
Local translation/context caches can contain recognized words and sentences;
they stay in the local data directory and are not telemetry. See
[performance notes](WINDOWS_PERFORMANCE.md) for the latest measured changes.
