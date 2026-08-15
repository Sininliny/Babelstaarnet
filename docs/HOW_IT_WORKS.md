# How Babelstårnet works

Design rules, recognition pipeline, and development notes. The
[README](../README.md) covers installing and using the app.

## Translation first

The bubble answers before it teaches:

- **The meaning leads.** It is the first and largest thing in the bubble, with
  no heading to read past. The Danish word sits underneath, so you can confirm
  the pointer landed where you meant.
- **Any word you point at is answered in full.** Whatever the app believes you
  know, the word under the pointer gets its meaning — being quietly tested on a
  word is never allowed to stand between you and reading. If the answer was not
  enough, `2` says so and brings back more English for that word.

  There used to be a fourth control that translated the whole line into English
  regardless of the profile. It is gone. A reader who wants the English of a
  whole line is asking for a translation rather than a bridge, which is not what
  this app is for, and nothing in the app read the fact that it had been pressed
  — a signal that strong about what someone cannot read should teach the profile
  something, and it taught it nothing. It would be worth having back on the day
  it does.
- **Nothing is asked of you.** The **Knew** / **Don’t know** controls sit in a
  fixed row above the answer, behind a rule, so the meaning is still the first
  thing you read inside the bubble. They are a permanent tool rather than a
  question: nothing about them changes as you read, and ignoring them for a
  whole session costs nothing. Their shortcuts stay live either way, and the
  menu-bar popover lists them.
- **Acting always answers back, and keeps answering.** Pressing a shortcut
  turns that control's key into a tick, and the tick stays as long as the word
  is on screen. Come back to the same word within five minutes and it is still
  there: what you did to a word is a fact about the word, not a receipt for the
  keypress. A word met again after that comes back clean.

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
- **Whole sentence**, below the pointer: the whole Danish sentence in its own
  word order and grammar, gathered from however many wrapped lines it is
  printed across, with English standing in for the words you cannot read yet.

Both use one frozen OCR snapshot, so the answer does not keep changing after the
pointer stops. `1` is **Knew**, `2` is **Don’t know**, and `3` pins the
bubbles.

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
  answers **Marked known** or **English restored** on the control that was
  pressed, and holds that answer for five minutes per word rather than flashing
  it for a second and a half. Marking a word known also gives that Danish word
  a short lift and glow. Confidence shows as a restrained
  fade of the *English* gloss, which is the part meant to go away; the Danish
  stays inside one perceptual step of full strength at every level so that
  knowing a word never makes it harder to read.
- The word under the pointer is marked in the sentence below, by a rule in the
  accent colour and nothing else in either panel uses that colour. The two
  panels answer the same question and had nothing tying them together: the
  sentence repeated the word among thirty others, or replaced it with English
  somewhere mid-line, and the reader had to find it before the answer meant
  anything. Where the word was replaced, the mark goes on the English standing
  in for it — which is also why adjacent English is no longer run together
  across it.
- The swap tint is drawn only while swaps are the exception. A faint tint marks
  the words English stands in for, but said about nearly every word on the line
  — where every reader starts, and stays for a long while — it stops being a
  mark and becomes the background: a line of highlighter with two Danish words
  floating outside it. Past about two thirds of the line the tint is dropped and
  the sentence is set plain, so the mark leaves the design on its own as the
  profile fills in and the Danish returns.
- Words sit on a shared baseline, not a shared top edge, and the tint is painted
  outside each word's own box. Both were costing the sentence its rhythm:
  substituted runs measured six points wider than the words beside them, so a
  line of running text was set with two different word spaces and read as a row
  of chips rather than as a sentence.
- The bubble text has its own ground inside the material. A panel is read over
  whatever the page behind it happens to be, and the hardest case is the
  ordinary one — a white article under a system running in dark appearance —
  where the material alone put grey text on grey with the page's own black text
  showing through and interleaving with the sentence. The glass still frames the
  panel; the words sit on the panel's own background colour.
- Pointing at a word the profile counts as known answers **Known** rather than
  nothing. Withholding the English is the whole point of counting a word as
  known, but the panel that appears still has to say something: it was returning
  a box holding three buttons and the Danish word, on top of the line being
  read.
- The bridge runs over the sentence, not over the line. Vision hands back one
  visual line at a time, and a line is wherever the column happened to wrap:
  bridging it alone produced "Ability i digital learning environments,
  including." — a fragment beginning after the subject and stopping before the
  verb, which teaches neither the word order it exists to preserve nor the
  meaning that was asked about. The lines above and below the pointer are
  therefore joined until a real Danish sentence stop is found. A period is a
  weak signal in the language — "den 15. september", "bl.a.", "kl. 13" — so a
  stop counts only when what follows opens a sentence, which in Danish means a
  capital. The walk is skipped entirely when the hovered line already stops on
  both sides of the word, so a sentence that fits on one line costs nothing:
  the lines kept for translation are exactly the lines the sentence occupies.
- The adaptive sentence bridge preserves Danish word order and grammar across
  that sentence. Established words remain Danish, learning words
  are replaced by their English in place, keeping the Danish word order around
  them. Every word the reader cannot read is replaced, so the sentence is
  always readable end to end; what adapts is the profile, and words return to
  Danish one at a time as they are learned. A cap of one to five substitutions was
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
  question about it and is answered in full; the rule only withholds anchors
  from the rest of the line
- Two coordinated bubbles with no headings on either: a compact word panel above
  the hovered word and a wider sentence panel below it. The word panel leads
  with the English meaning, keeps the Danish word beneath it, and adds a concise
  Danish explanation with English only under concepts the reader does not yet
  know. Each panel can be enabled independently in the menu-bar popover or
  Settings, and all content wraps instead of being shortened. Both use one
  frozen OCR snapshot, so background rescans cannot change them while the
  pointer is still. `1` marks a word known, `2` marks it unknown and shows extra
  English, and `3` pins or unpins the visible bubbles.
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
- Bubbles keep clear of every line the sentence is printed on, not only the line
  under the pointer, so the panel explaining a wrapped sentence no longer lands
  on the rest of it
- Guaranteed meaning placement on dense pages; speech never runs without a
  visible learning result
- Native Liquid Glass on macOS 26+, with a material-glass fallback on macOS 15
- Customizable global activation/deactivation shortcut (`Fn+Z` by default)
- Distinct active and inactive menu-bar icons
- Movement-driven refresh with a low-frequency stationary fallback for scrolling
  and screen changes
- Latest-pointer scheduling cancels obsolete OCR processes, translates the
  lines the focused sentence is printed on and nothing else, and reuses exact
  unchanged captures without allowing an older result to replace the current
  bubble
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
service. [SECURITY.md](SECURITY.md) accounts for how that is enforced, what is
stored on disk, which binaries the app will execute, and what is still open.

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
                                   focused sentence bounds
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
layout, and app state are separate targets rather than separate folders:

| Target | Holds | Depends on |
| --- | --- | --- |
| `BabelCore` | recognized text, the language-pack value types, shared helpers | — |
| `BabelOCR` | Vision and Tesseract adapters, routing and quality policies | `BabelCore` |
| `BabelTranslate` | the local Argos worker, translation quality | `BabelCore` |
| `BabelLexicon` | the system dictionary | `BabelCore` |
| `BabelSpeech` | speech synthesis | — |
| `LanguageDanish` | Danish, as data | `BabelCore` |
| `BabelstaarnetKit` | overlay, learner profile, capture, app state | all of the above |

None of the capability targets depends on `LanguageDanish`, and none of them
names a language: each is handed a `SourceLanguage` or `TargetLanguage` value
by the app, which is the only place a language is chosen. Adding a language is
adding a target beside `LanguageDanish` — the package graph is what keeps a
service from quietly reaching for a Danish table instead.

The capture planner uses cursor speed and
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

## Development

- macOS 15 or newer
- Swift 6.2 toolchain
- Screen Recording permission

Xcode is not required to build from the command line, although it is recommended
for development and signing.

```sh
make test
make test-runtime
make benchmark-ocr
make run
make release
make readme-images
```

`make run` builds and ad-hoc signs `dist/Babelstaarnet.app`, then launches it.
`make release` produces `Babelstaarnet.app.zip` and its checksum under `dist/`.

`make test-runtime` renders a Retina-scale cursor crop containing dark, light,
and colored Danish text. It verifies the focused Vision response, that the
focused reading preserves Danish diacritics, the complete Tesseract fallback,
unchanged-capture reuse, cancellation, repeated translation through the
persistent Argos worker, and the adaptive word-explanation resources.

`make readme-images` redraws the mark and the interface illustration in
`docs/images/`. The illustration is built from the overlay's own constants —
bubble widths, paddings, corner radii, type sizes — so it is a picture of the
real design rather than an impression of it, but it is a rendering and not a
screen capture: the translucent panel material cannot be reproduced offscreen
and is stood in for by a near-opaque fill. Change a bubble's geometry and this
should be run again.

`make benchmark-ocr` scores recognition across twenty rendered reading
situations that vary one property at a time: polarity, contrast, chroma,
background, density, and typography. Each scenario reports whether the word
under the pointer was located with usable bounds and how much of the
surrounding sentence was recovered, and the run is compared against a recorded
baseline so a colour or format regression is visible rather than inferred.

Power saving is enabled by default. It can be disabled under **Settings →
Reading → Pause screen reading when idle**. While suspended, detection remains
logically active, the current hover data stays available, and no new screenshot
or OCR request is made.

When the Apple translation fallback is used, the first translation may prompt
macOS to download its Danish → English language pack. It then works offline.

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

## Current MVP limitations

- The first release installs open-source engines separately rather than
  embedding their large binaries and language models in the `.app`.
- macOS may need the app to be relaunched after Screen Recording permission is
  changed.
