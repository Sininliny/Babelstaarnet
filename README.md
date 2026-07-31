# Babelstårnet

Babelstårnet is a private, local-first macOS learning overlay. It reads Danish
text visible across your displays and turns each Danish OCR word into a
hoverable learning target. Hovering speaks the original Danish word and shows
its English meaning and definition beside—not over—the source.

This repository currently contains the first working MVP for Danish → English.

## What works

- Cursor-local capture with ScreenCaptureKit instead of repeatedly scanning the
  whole display
- Adaptive capture bounds that expand for large text, contract for small text,
  and look ahead in the direction of pointer movement
- Danish OCR with [Tesseract](https://github.com/tesseract-ocr/tesseract)
  and the open `dan` model
- Contrast-adaptive OCR passes for dark, light, and colored text
- Adaptive small-text OCR for dense PDFs and forms: table rules are removed,
  tiny glyphs are enlarged within a bounded pixel budget, and cell text is
  recognized with sparse layout analysis
- Danish → English translation with
  [Argos Translate](https://github.com/argosopentech/argos-translate)
- Independent learning layers: show or hide Danish → English translation, then
  freely combine it with a Beginner gloss, Easy Danish explanation, full
  English definition, or no explanation
- Easy Danish hints from a local learner lexicon plus
  [Princeton WordNet](https://wordnet.princeton.edu/) definitions translated
  through the local English → Danish Argos model
- Cursor-only learning bubble; no screen full of translated captions
- Per-word OCR bounds and pointer tracking for selectable text and text in images
- English definitions from the local macOS Dictionary
- Danish pronunciation through the local AVSpeechSynthesizer voice
- Guaranteed meaning placement on dense pages; speech never runs without a
  visible learning result
- Native Liquid Glass on macOS 26+, with a material-glass fallback on macOS 15
- Global Fn+Z activation/deactivation
- Distinct active and inactive menu-bar icons
- Movement-driven refresh with a low-frequency stationary fallback for scrolling
  and screen changes
- Automatic idle suspension: screen capture and OCR pause after five seconds
  without keyboard or pointer input and resume on the next input
- Persistent warmed Argos worker and translation cache for low hover latency
- One independent overlay per display to preserve OCR coordinate alignment
- First-launch dashboard with permission and engine readiness checks
- Compact monochrome dashboard with one primary learning control
- In-app installation and rechecking for the open-source engines
- Zero-setup Apple Vision and Translation fallbacks when Tesseract or Argos is
  not installed

No screenshot, recognized text, definition, or audio is sent to a remote
service.

## Install the app

Download the latest DMG from
[GitHub Releases](https://github.com/Sininliny/Babelstaarnet/releases), open it,
and drag **Babelstaarnet.app** to **Applications**. On first launch:

1. Click **Set up Babelstårnet**.
2. Enable Babelstårnet in the System Settings page that opens.
3. Return to the app and relaunch if macOS requests it.
4. Click **Start hover learning**, or press `Fn+Z`.

No account, terminal, or engine installation is required. Apple Vision and
Translation provide an entirely on-device zero-setup path. The open-source
Tesseract and Argos engines remain available as an optional installation under
Settings.

Releases built without an Apple Developer ID are preview builds. macOS may
require Control-clicking the app and choosing **Open** once. Signed and
notarized releases open normally.

## Development requirements

- macOS 15 or newer
- Swift 6.2 toolchain
- Screen Recording permission

Xcode is not required to build from the command line, although it is recommended
for development and signing.

## Screen Recording identity

Local builds are ad-hoc signed with the explicit designated requirement
`identifier "dev.sinin.babelstaarnet"`. This keeps the identity macOS uses for
Screen Recording stable across `make app` rebuilds without installing or
trusting a private certificate.

If Screen Recording was granted to an older build that used a CDHash
requirement, remove or toggle that old Babelstårnet entry once, launch the
current bundle, enable Babelstårnet again, and relaunch. Later local rebuilds
retain the designated requirement.

## Optional open-source local engines

Use **Install engines** in Settings if you prefer the open-source pipeline. The
packaged installer installs Tesseract with Danish language data through
Homebrew, creates a private Python 3.12 environment under Application Support,
and downloads the Danish ↔ English Argos models plus local WordNet data.

The same setup can be run from the repository:

```sh
make install-engines
```

This is a one-time optional setup. After the packages are installed, both
engines work without network access. If you skip it, Babelstårnet remains
functional with Apple's on-device Vision and Translation frameworks.

Argos state is kept under:

```text
~/Library/Application Support/Babelstaarnet/
```

## Build and run

```sh
make test
make test-runtime
make run
make release
```

`make run` builds and ad-hoc signs `dist/Babelstaarnet.app`, then launches it.
`make release` produces a drag-to-Applications DMG and checksum under `dist/`.
On first use:

1. Choose **Allow access** in the menu-bar popover.
2. Enable Babelstårnet under **System Settings → Privacy & Security → Screen
   Recording**.
3. Relaunch the app if macOS requests it.
4. Choose **Activate hover learning** or press `Fn+Z`.
5. In Settings, independently choose **Translate: Danish → English / None** and
   **Explain: Beginner / Easy Danish / English / None**.
6. Hover a Danish word to hear it and see the selected explanation.
7. Press `Fn+Z` again to deactivate.

Power saving is enabled by default. It can be disabled under **Settings →
Learning → Pause screen reading when idle**. While suspended, detection remains
logically active, the current hover data stays available, and no new screenshot
or OCR request is made.

`make test-runtime` renders a Retina-scale cursor crop containing dark, light,
and colored Danish text, reads it with the installed Tesseract engine, and
checks repeated translations through the persistent Argos worker. The runtime
checks enforce a sub-two-second OCR budget and a sub-one-second warmed
translation budget.

When the Apple translation fallback is used, the first translation may prompt
macOS to download its Danish → English language pack. It then works offline.

## Architecture

```text
cursor movement → adaptive local crop → contrast-adaptive Tesseract
                                             │
                                    word bounds + size estimate
                                             │
                         cached persistent Argos translation
                                             │
                         English meaning / Easy Danish WordNet hint
                                             │
                                    click-through overlay
                                             │
                                      hover hit-test
                                          ┌──┴──┐
                                          ▼     ▼
                                    Dictionary  local TTS
```

The capture, OCR, translation, dictionary, speech, overlay layout, and app state
are separate. The capture planner uses cursor speed and the most recently
observed text height to choose a local region, then retries with a larger crop
only when words touch its boundary or no text is found. Tesseract emits TSV
word geometry from normal and inverted high-contrast passes. Only uncached
unique Danish words are sent to the warmed local Argos worker. The app creates
an independent click-through overlay per display and renders nothing until the
cursor enters an OCR word box. Apple adapters are fallbacks, not network
services.

## Current MVP limitations

- The first release installs open-source engines separately rather than
  embedding their large binaries and language models in the `.app`.
- macOS may need the app to be relaunched after Screen Recording permission is
  changed.

## Name

“Babelstårnet” is Danish for “the Tower of Babel.” The repository keeps the
ASCII spelling `Babelstaarnet`.
