# Babelstårnet

**Hover any Danish word. Get the meaning. Keep reading.**

Babelstårnet is a local-first macOS translator for Danish. Point at a word
anywhere on screen — a website, a PDF, a form, text inside an image — and its
meaning appears where you are already looking. Nothing to select, paste, or
submit.

It is a translator first. What makes it different is what it does *while* you
use it: because every Danish word you can already read stays Danish, and because
the app quietly remembers which words keep coming back to you, ordinary use
turns into ordinary learning. That part runs in the background and never asks you for
anything.

## Translation first

The bubble answers before it teaches:

- **The meaning leads.** It is the first and largest thing in the bubble, with
  no heading to read past. The Danish word sits underneath, so you can confirm
  the pointer landed where you meant.
- **You can always get everything.** Press `4` with a bubble open and every word
  on the line is translated, regardless of what the app thinks you know. Press
  it again to go back. It is a reading mode, so it stays on until you turn it
  off.
- **Nothing is asked of you.** The **Knew** / **Don’t know** controls sit in a
  fixed row above the answer, behind a rule, so the meaning is still the first
  thing you read inside the bubble. They are a permanent tool rather than a
  question: nothing about them changes as you read, and ignoring them for a
  whole session costs nothing. Their shortcuts stay live either way, and the
  menu-bar popover lists them.
- **Acting always answers back.** The bubble never prompts, but pressing a
  shortcut confirms itself inline.

## Learning, without being a lesson

Four rules keep the learning underneath the translation:

1. **Danish carries the sentence.** Word order and grammar stay Danish, and
   every word the reader knows stays Danish with it. Only the words they cannot
   read are swapped for English, in place, so what is left is one line to read
   rather than two texts to reconcile. The word being pointed at is still shown
   in Danish in the word panel, under its meaning.
2. **English is scaffolding, not the product.** Babelstårnet adds a few concise
   English anchors rather than translating everything by default, and the
   anchors are what fade as a word becomes familiar, giving the Danish back one
   word at a time. Whatever Danish remains is fully legible at every level.
3. **Help follows the reader.** Unknown words receive support; familiar words
   need less; well-known words stay Danish-only. Reading is what moves this —
   spaced encounters in different contexts count, repeated hovering does not.
4. **Feedback is exceptional, not homework.** **Knew** and **Don’t know** exist
   for the times the app judged a word wrong, not as a task to complete.

The two panels serve different reading problems and can be used separately:

- **Word meaning**, above the pointer: what the word means, plus a concise
  Danish explanation with English standing in for the concepts you do not yet
  know.
- **Whole sentence**, below the pointer: the Danish line in its own word order
  and grammar, with one or two English anchors when the sentence is mostly
  familiar, growing to five when the text is genuinely difficult.

Both use one frozen OCR snapshot, so the answer does not keep changing after the
pointer stops. `1` is **Knew**, `2` is **Don’t know**, `3` pins the bubbles, and
`4` shows all English.

## What works

- Cursor-local capture with ScreenCaptureKit instead of repeatedly scanning the
  whole display
- Adaptive capture bounds that expand for large text, contract for small text,
  and look ahead in the direction of pointer movement
- Danish OCR with [Tesseract](https://github.com/tesseract-ocr/tesseract)
  and the open `dan` model
- Accurate Apple Vision recognition for the word under the pointer, with the
  complete Tesseract fallback still available. The faster recognition level is
  deliberately not used for reading: measured against rendered Danish crops it
  returned nothing below roughly 13 px text, below a 60-step luminance
  difference, or on saturated text over a saturated background, and where it
  did return text it dropped æ, ø, and å while reporting unchanged confidence.
  A stripped diacritic changes which Danish word gets translated
- Colour-adaptive recognition that derives its threshold from the crop instead
  of assuming dark text on a light page. Each capture is projected onto its own
  direction of greatest colour variance, split with Otsu's method, and oriented
  dark-on-light, so dark mode, saturated banners, secondary labels a few
  luminance steps from their panel, and red-on-green text all separate. This
  runs as a second pass only when the original capture could not be read
- Fine print is re-read from an enlarged crop when the line under the pointer is
  small, which is what restores diacritics that dense forms and tables lose.
  Only that line is cropped and enlarged, by as much as its own type size calls
  for rather than a fixed doubling, and the refined line is substituted back
  into the reading rather than replacing it, so the rest of the sentence
  survives a crop that no longer holds it. The two dense-table scenarios in
  `make benchmark-ocr` fell from 137 and 150 ms to 78 and 73 ms at unchanged
  scores
- No pass is run twice. Reaching the whole-capture fallback used to re-run the
  accurate and colour-separated passes the focused attempts had already made and
  discarded: three accurate Vision passes where two answer the same question.
  That path is what a hover over a blank area takes, which is the most common
  place a pointer sits while reading. Best of five sweeps, it fell from 313 ms
  to 267 ms; individual runs vary by more than that margin, but the pass count
  does not
- The smallest text worth searching for is stated in pixels rather than as a
  share of the capture, so the same text is looked for the same way whether the
  crop around the pointer came out short or tall
- Adaptive small-text OCR for dense PDFs and forms: table rules are removed
  while filled areas are kept, antialiased strokes are strengthened, tiny glyphs
  are enlarged to a reliable target size within a bounded pixel budget, and cell
  text is recognized with sparse layout analysis
- A corrupted word no longer discards the line it appeared in, so a colour
  failure on one word cannot take the pointer's word with it
- Danish → English translation with
  [Argos Translate](https://github.com/argosopentech/argos-translate)
- Meaning-first bubbles with no mode selection: the English answer is the
  headline, the Danish word sits under it, and familiar words simply need less
  English than new ones
- A full-English reveal on `4`, which translates every word on the line no
  matter what the profile believes, and stays on until it is turned off. The
  profile is only overridden for display; the reveal records nothing
- A private adaptive learning profile with a hidden knowledge level from 0 to
  5. One **Knew** action removes unnecessary English for the focused word; one
  **Don’t know** action immediately restores full help. Spaced encounters in
  different contexts gradually reduce support through the learning levels,
  while repeated hovering on the same text contributes no knowledge. Passive
  learning stops before mastery, and a later explicit confirmation can make a
  known word stable. Levels 0–2 put a concise English word in place of the
  Danish one, level 3 quietly tests comprehension with no help at all, and
  levels 4–5 stay Danish. A word therefore returns to Danish as it is learned,
  which is the only progress signal the reader ever sees. Internal
  levels are intentionally absent from the reading bubbles. A testing-level
  word keeps a faint direct meaning in the focused word panel so passive
  learning never becomes a barrier to translation. Sentence-only mode carries
  the same focused safety meaning instead of silently removing it. Feedback
  briefly confirms **Marked known** or **English restored** in the active
  bubble whether or not the controls are on screen. Marking a word known also
  gives that Danish word a short lift and glow. Confidence shows as a restrained
  fade of the *English* gloss, which is the part meant to go away; the Danish
  stays inside one perceptual step of full strength at every level so that
  knowing a word never makes it harder to read.
- The adaptive sentence bridge preserves Danish word order and grammar across
  the visible source line. Established words remain Danish, learning words
  are replaced by their English in place, keeping the Danish word order around
  them. Every word the reader cannot read is replaced, so the line is always
  readable end to end; what adapts is the profile, and words return to Danish
  one at a time as they are learned. A cap of one to five substitutions was
  tried and removed — it left the unreplaced words stranded in a line that was
  no longer Danish either, so the reader got "the period of reflection på 6
  months fra time", readable in neither language. English set beneath the
  Danish rather than in place of it was removed for the same reason: a word
  someone cannot read is not made readable by being left in place with a note
  attached.
- Danish's closed classes — articles, pronouns, prepositions, conjunctions, and
  the auxiliary and copula verbs — are translated from a table rather than by
  the model. Handed a single word with no sentence around it, Argos returns
  "no" for `er`, and once English stands in place of the Danish a wrong answer
  is the only thing left. These classes are small and stable, so the citation
  form is simply written down. A word with an explicit accepted set keeps it:
  `for` may still come back as "too", because "for meget" is "too much"
- Anchors are not spent on Danish's closed classes — articles, pronouns,
  prepositions, conjunctions, and the auxiliary and copula verbs. They are the
  first fifty words of the language, and they are also where word-at-a-time
  translation is least trustworthy, because their English equivalent is decided
  by the construction around them: asked on its own, `er` came back as `no`. A
  line reading "Det er en betingelse for, at CPR-kontoret kan tildele" spent two
  of three anchors on `er` and `en`. Pointing at one of these words is still a
  question about it and is answered in full, as is asking for all English; the
  rule only withholds anchors from the rest of the line
- Two coordinated bubbles with no headings on either: a compact word panel above
  the hovered word and a wider sentence panel below it. The word panel leads
  with the English meaning, keeps the Danish word beneath it, and adds a concise
  Danish explanation with English only under concepts the reader does not yet
  know. Each panel can be enabled independently in the menu-bar popover or
  Settings, and all content wraps instead of being shortened. Both use one
  frozen OCR snapshot, so background rescans cannot change them while the
  pointer is still. `1` marks a word known, `2` marks it unknown and shows extra
  English, `3` pins or unpins the visible bubbles, and `4` toggles full English.
  Holding Option keeps them open while the pointer moves to the controls. After
  0.75 seconds without input, they are held temporarily; any pointer or keyboard
  input releases that temporary hold. Every shortcut and the hold modifier can
  be changed in Settings; bubble shortcuts exist only while a bubble is visible.
- Feedback controls in a fixed row at the top of the word panel, above the
  answer and separated from it by a rule. They are never conditional, so they
  cannot flicker and the answer under them never reflows. Revealing them on
  demand was tried first and removed: it derived from the temporary bubble hold,
  which any system input releases — a keystroke, a scroll, a fingertip settling
  on a trackpad — after which it is re-earned only following another 0.75 s of
  complete stillness. Reading a page with the pointer parked produces that
  pattern roughly once a second, so the row appeared and vanished under a reader
  who had never left the word. Position, not visibility, now keeps them out of
  the reading path. The sentence panel carries no controls; it still confirms a
  shortcut inline, because the shortcuts work whether or not the word panel is
  switched on
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
- When reading stops on its own, the menu bar says why and offers to start
  again. A failure ends the session completely rather than leaving the bubbles
  answering from the last thing they read
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
4. Click **Start translating**, or press `Fn+Z` (the default shortcut).

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
4. Choose **Start translating** or press `Fn+Z` by default.
5. Hover a Danish word to hear it and see what it means.
6. With a bubble visible, press `4` to translate the whole line, `1` for
   **Knew**, `2` for **Don’t know**, or `3` to pin it. The same four are buttons
   in the row at the top of the word panel, and the shortcuts work whenever a
   bubble is on screen — including when the word panel is switched off and there
   is no row. These shortcuts and the hold modifier are editable under
   **Settings → Shortcuts**.
7. Press the activation shortcut again to deactivate.

Power saving is enabled by default. It can be disabled under **Settings →
Reading → Pause screen reading when idle**. While suspended, detection remains
logically active, the current hover data stays available, and no new screenshot
or OCR request is made.

`make test-runtime` renders a Retina-scale cursor crop containing dark, light,
and colored Danish text. It verifies the focused Vision response, that the
focused reading preserves Danish diacritics, the complete Tesseract fallback,
unchanged-capture reuse, cancellation, repeated translation through the
persistent Argos worker, and the adaptive word-explanation resources.

`make benchmark-ocr` scores recognition across twenty rendered reading
situations that vary one property at a time: polarity, contrast, chroma,
background, density, and typography. Each scenario reports whether the word
under the pointer was located with usable bounds and how much of the
surrounding sentence was recovered, and the run is compared against a recorded
baseline so a colour or format regression is visible rather than inferred.

When the Apple translation fallback is used, the first translation may prompt
macOS to download its Danish → English language pack. It then works offline.

## Architecture

```text
cursor movement → adaptive local crop → accurate Vision OCR
                                             │ unreadable colours
                                             ▼
                                   colour-separated retry
                                             │ still unreadable
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
The pointer's word is read by accurate Vision; when its colours defeat that, one
colour-separated retry runs before any external engine starts. Tesseract retains
TSV word geometry from raw, colour-separated block, automatic-layout, and
conditional small-text passes for targets that need more analysis, and competing
readings of the same place are ranked by the confidence Tesseract reports rather
than by which string is longest. Only uncached unique Danish words from the
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
