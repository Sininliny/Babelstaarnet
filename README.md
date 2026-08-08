# Babelstårnet

**Understand Danish without escaping into English.**

Babelstårnet is a local-first macOS reading layer for learning Danish. It reads
the text under the pointer and gives the learner enough English to recover the
meaning, but never replaces the Danish sentence. You are supported through the
source language instead of being given an English route around it.

It is intentionally not a conventional translator, vocabulary-card system, or
parallel subtitle layer. Its purpose is language transfer: keep the learner
reading Danish, place English only beneath concepts that are not yet known, and
quietly remove that help as comprehension grows.

## The gap between Babelstårnet and a translator

A normal translator optimizes for obtaining the answer in another language.
That is useful for communication, but it also makes it easy to stop processing
the source language. Babelstårnet optimizes for a different outcome: obtaining
the meaning while still having to read and understand Danish.

| | Conventional translator | Babelstårnet |
| --- | --- | --- |
| Primary text | The translated language | The original Danish |
| English help | Replaces the sentence or appears as a full parallel version | Appears only under selected unknown concepts |
| Learner model | Usually the same output for every reader | A private knowledge level for each word |
| Change over time | Repeating the request gives the same help | English fades as a word becomes known and returns immediately after **Don’t know** |
| Interaction | Select, copy, or submit text | Hover the Danish text already on screen |
| Reading pressure | The source can be skipped | Meaning is available, but Danish remains necessary |
| Processing | Depends on the translation service | Screen reading, learning state, translation, and speech remain local |

## Meaning without escape

The learning design follows four rules:

1. **Danish never disappears.** The source word and Danish sentence structure
   remain the visual foundation.
2. **English is scaffolding, not the product.** Babelstårnet adds at most a few
   concise English meaning anchors instead of translating everything. A new or
   passively tested focused word receives its direct English meaning
   immediately; the Danish sentence is never replaced.
3. **Help follows the learner.** Unknown words receive support; learning words
   are tested with less support; known words remain Danish-only.
4. **Feedback is exceptional, not homework.** Hovering is passive. The learner
   presses **Knew** or **Don’t know** only when the bridge has judged a word
   incorrectly.

The two independent bridges serve different reading problems:

- **Word bridge**, above the pointer, explains the focused word in concise
  Danish and adds English only for concepts the learner does not yet know.
- **Sentence bridge**, below the pointer, preserves Danish order and grammar.
  It uses one or two English anchors when the sentence is mostly familiar and
  can grow to five when the text is genuinely difficult.

Both bubbles use one frozen OCR snapshot, so the support does not keep changing
after the pointer stops. `1` means **Knew**, `2` means **Don’t know**, and `3`
pins the bubbles. The result is a reading tool that makes Danish understandable
without making Danish optional.

## What works

- Cursor-local capture with ScreenCaptureKit instead of repeatedly scanning the
  whole display
- Adaptive capture bounds that expand for large text, contract for small text,
  and look ahead in the direction of pointer movement
- Danish OCR with [Tesseract](https://github.com/tesseract-ocr/tesseract)
  and the open `dan` model
- A focused Apple Vision fast path for clear text under the pointer, followed
  by a bounded accurate-Vision retry for tiny or uncertain targets; the
  complete Tesseract fallback remains available
- Contrast-adaptive OCR passes for dark, light, and colored text
- Adaptive small-text OCR for dense PDFs and forms: table rules are removed,
  antialiased strokes are strengthened, tiny glyphs are enlarged to a reliable
  target size within a bounded pixel budget, and cell text is recognized with
  sparse layout analysis
- Danish → English translation with
  [Argos Translate](https://github.com/argosopentech/argos-translate)
- One Danish-first learning translator with no mode selection: familiar words
  stay Danish while English appears only where it is needed for understanding
- A private adaptive learning profile with a hidden knowledge level from 0 to
  5. One **Knew** action removes unnecessary English for the focused word; one
  **Don’t know** action immediately restores full help. Spaced encounters in
  different contexts gradually reduce support through the learning levels,
  while repeated hovering on the same text contributes no knowledge. Passive
  learning stops before mastery, and a later explicit confirmation can make a
  known word stable. Danish always remains visible: levels 0–2 attach a concise
  English gloss beneath selected Danish words, level 3 quietly tests
  comprehension without a gloss, and levels 4–5 remain Danish-only. Internal
  levels are intentionally absent from the reading bubbles. A testing-level
  word keeps a faint direct meaning in the focused Word bridge so passive
  learning never becomes a barrier to translation. Sentence-only mode carries
  the same focused safety meaning instead of silently removing it. Feedback
  briefly confirms **Marked known** or **English restored** directly in the
  active bubble. Marking a word known also gives that Danish word a short lift
  and glow. Danish words use a restrained gray progression so different
  confidence levels are perceptible without adding labels or progress numbers.
- The adaptive sentence bridge preserves Danish word order and grammar across
  the visible source line. Established words remain Danish, learning words
  receive a small interlinear English gloss. The support budget adapts from one
  to five anchors according to how much of the sentence is unfamiliar.
- Two coordinated learning bubbles: a compact adaptive word explanation stays
  above the hovered word while a wider sentence bridge stays below it. The word
  bridge preserves a concise Danish explanation and attaches English only
  beneath concepts the learner does not yet know. Each bridge can be enabled
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
- Latest-pointer scheduling cancels obsolete OCR processes, translates the
  focused source line needed by the current bubble, and reuses exact unchanged
  captures without allowing an older result to replace the current bubble
- Adaptive power saving: OCR refreshes back off while the pointer is still,
  stop while a bubble is held, and suspend after five seconds without input
- Capture metadata and required Argos workers warm in parallel before the first
  scan. A short bounded grace period avoids a cold restart after an accidental
  toggle, while unused workers still shut down automatically
- Bounded least-recently-used translation and explanation caches, batched
  exposure persistence, cached display metadata, and bridge-aware processing
  prevent long sessions from accumulating unbounded memory or doing work for
  disabled bubbles
- One independent overlay per display to preserve OCR coordinate alignment
- Menu-bar setup with permission and engine readiness checks
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
and colored Danish text. It verifies the focused Vision response, the complete
Tesseract fallback, unchanged-capture reuse, cancellation, repeated translation
through the persistent Argos worker, and the adaptive word-explanation
resources.

When the Apple translation fallback is used, the first translation may prompt
macOS to download its Danish → English language pack. It then works offline.

## Architecture

```text
cursor movement → adaptive local crop → focused Vision OCR
                                             │ uncertain / small text
                                             ▼
                                  contrast-adaptive Tesseract
                                             │
                                  focused source-line bounds
                                             │
                              cached warmed Argos translation
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
Clear pointer targets use a bounded Vision fast path. Tesseract retains TSV
word geometry from normal, inverted, chroma, and conditional small-text passes
for targets that need more analysis. Only uncached unique Danish words from the
focused source line are sent to the warmed local Argos worker. The app keeps
hit-test data per display and renders one small,
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
