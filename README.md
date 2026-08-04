# Babelstårnet

Babelstårnet is a private, local-first macOS learning overlay. It reads Danish
text visible across your displays and turns each Danish OCR word into a
hoverable learning target. Hovering speaks the original Danish word and shows
the surrounding Danish sentence with only the English support the learner
currently needs, beside—not over—the source.

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
- One Danish-first learning translator with no mode selection: familiar words
  stay Danish while English appears only where it is needed for understanding
- A private adaptive learning profile that treats hovering as exposure only,
  gives every word a bounded knowledge level from 0 to 5, raises it by one for
  **Knew**, lowers it by one for **Don’t know**, gradually reduces English
  support, and can be reset from Settings. Retention is based only on explicit
  review: higher levels last longer, while merely hovering never refreshes a
  word’s knowledge clock. Level 0 uses English substitution, levels 1–3 show
  Danish beside concise English, and levels 4–5 keep the word Danish. The
  bubble names the stages New, Recognizing, Learning, Mostly known, Known, and
  Mastered.
- The adaptive sentence bridge preserves Danish word order and grammar across
  the visible source line. Established words remain Danish, learning words
  receive a brief outlined English bridge, and new meaning-bearing words use
  concise English support.
- Two coordinated learning bubbles: a compact adaptive word explanation stays
  above the hovered word while a wider sentence bridge stays below it. The word
  bridge preserves a concise Danish explanation and replaces only concepts the
  learner does not yet know with outlined English. Each bridge can be enabled
  independently in the menu-bar popover or Settings, and all content wraps
  instead of being shortened. Both use one frozen
  OCR snapshot, so background rescans cannot change them while the pointer is
  still. `1` marks a word known, `2` marks it unknown and shows extra English,
  and `3` pins or unpins the visible bubbles. Holding
  Option keeps them open while the pointer moves to the controls. After 0.75
  seconds without input, they are held temporarily; any pointer or keyboard
  input releases that temporary hold. Every shortcut and the hold modifier can
  be changed in Settings; bubble shortcuts exist only while a learning bubble
  is visible.
- Versioned local JSON export/import for backing up or moving the adaptive
  learning profile without exporting screenshots or source sentences; imports
  merge idempotently with existing progress
- Cursor-only learning bubble; no screen full of translated captions
- Per-word OCR bounds and pointer tracking for selectable text and text in images
- Optional extra English help from the local macOS Dictionary after **Don’t
  know** feedback
- Danish pronunciation through the local AVSpeechSynthesizer voice
- Guaranteed meaning placement on dense pages; speech never runs without a
  visible learning result
- Native Liquid Glass on macOS 26+, with a material-glass fallback on macOS 15
- Customizable global activation/deactivation shortcut (`Fn+Z` by default)
- Distinct active and inactive menu-bar icons
- Movement-driven refresh with a low-frequency stationary fallback for scrolling
  and screen changes
- Adaptive power saving: OCR refreshes back off while the pointer is still,
  stop while a bubble is held, and suspend after five seconds without input
- Persistent warmed Argos worker and translation cache for low hover latency
- Bounded least-recently-used translation and explanation caches, batched
  exposure persistence, cached display metadata, and bridge-aware processing
  prevent long sessions from accumulating unbounded memory or doing work for
  disabled bubbles
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
4. Click **Start hover learning**, or press `Fn+Z` (the default shortcut).

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
and downloads Danish → English and English → Danish Argos models plus local
WordNet data for adaptive word explanations.

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
4. Choose **Activate hover learning** or press `Fn+Z` by default.
5. Hover a Danish word to hear it and see the adaptive sentence bridge.
6. With a learning card visible, use `1` for **Knew**, `2` for **Don’t know**,
   or `3` to pin it. Hold Option while moving to its controls. Leaving the
   pointer still temporarily holds the bubble until the next input. These
   shortcuts and the hold modifier are editable under **Settings → Shortcuts**.
7. Press the activation shortcut again to deactivate.

Power saving is enabled by default. It can be disabled under **Settings →
Learning → Pause screen reading when idle**. While suspended, detection remains
logically active, the current hover data stays available, and no new screenshot
or OCR request is made.

`make test-runtime` renders a Retina-scale cursor crop containing dark, light,
and colored Danish text, reads it with the installed Tesseract engine, and
checks repeated translations through the persistent Argos worker and verifies
the adaptive word-explanation resources. The runtime checks enforce a
sub-two-second OCR budget and a sub-one-second warmed translation budget.

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
                         adaptive Danish + English sentence bridge
                                             │
                              nonactivating hover bubble
                                             │
                                      hover hit-test
                                          ┌──┴──┐
                                          ▼     ▼
                                    Dictionary  local TTS
```

The capture, OCR, translation, learner profile, dictionary, speech, overlay
layout, and app state are separate. The capture planner uses cursor speed and
the most recently observed text height to choose a local region, then retries
with a larger crop only when words touch its boundary or no text is found.
Tesseract emits TSV word geometry from normal and inverted high-contrast
passes. Only uncached unique Danish words are sent to the warmed local Argos
worker. The app keeps hit-test data per display and renders one small,
nonactivating interactive bubble only when the cursor enters an OCR word box.
Apple adapters are fallbacks, not network services.

## Current MVP limitations

- The first release installs open-source engines separately rather than
  embedding their large binaries and language models in the `.app`.
- macOS may need the app to be relaunched after Screen Recording permission is
  changed.

## Name

“Babelstårnet” is Danish for “the Tower of Babel.” The repository keeps the
ASCII spelling `Babelstaarnet`.
