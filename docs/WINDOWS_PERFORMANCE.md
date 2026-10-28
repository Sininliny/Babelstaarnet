# Windows performance work

The October 2026 optimization keeps capture, OCR, ordinary translation,
contextual explanation and speech independent. Model loading must not prevent
the first local or cached word result from appearing.

## Changes

- Unchanged images are compared directly against the owned OCR pixel snapshot.
  There is no full-image hash or new pixel-sized allocation on that path.
  The only unsafe code is the bounded row comparison while `LockBits` owns
  the native pointer; stride, region bounds and origin are checked.
- Pixel allocation/copy and the wait for the Windows compositor run away from
  the dispatcher. Only panel exclusion and restoration touch WPF windows.
- Inactive reading stops the polling timer. Idle reading checks for input at
  250 ms while active reading retains its 35 ms polling cadence.
- Sentence and explanation projections are reused until an answer or learning
  change invalidates them. Existing sentence layout nodes and native panel
  frames continue to be reused.
- Word Book uses a recycling virtualized list. Search and familiarity filters
  operate on data, while visible containers create row controls.
- Contextual meanings keep completed focused answers and partial sentence
  batches. Revisiting a sentence does not discard a batch because a later
  hover canceled its remaining work. Word-only mode skips sentence requests;
  familiar sentence words are skipped. The model process runs below normal
  priority. Bounded local contextual memory survives restart, stamped by the
  model manifest and prompts. Complete cached answers bypass inference and
  warm-up locks.

## Measurements and limits

Measurements use release builds on the development Windows PC, in-memory
fixtures and installed offline engines. They are not service-level guarantees
or full desktop hover timings. Cold model loading varies with filesystem and
GPU caches. Do not mix it with warmed inference results.

The original unchanged 3840 × 2160 OCR path allocated about 33 MB per check and
took about 20.8 ms. The revised path allocated 248 bytes and took about 2.7 ms
in the final same-machine sample (3.9 ms in the first sample). JSON measurements are
generated into `build/` with `--benchmark`; they remain untracked.

A 5,000-entry Word Book initially realized 7 rows. Loading, layout, scrolling
to the end and applying the Known filter completed in about 54–76 ms in the
fixture. CI checks row realization bounds rather than this machine-specific
duration. Actual reading speed still depends on capture, OCR text quality,
model readiness and the surrounding desktop.

Run the commands in [the development guide](DEVELOPMENT.md) to reproduce the
measurements. Keep audio muted, avoid concurrent builds/inference, and compare
the same fixture and configuration before drawing a conclusion.

## Reading quality, 0.6.4

Windows now starts with a wider hover crop and expands a clipped focused line
even when the pointed word was recognized. A successful hit is not evidence
that the rest of the sentence was captured. Small images are supersampled up
to 2× within the Windows OCR dimension limit; returned boxes and pixel-cache
comparisons continue to use physical source coordinates. Large monitor images
retain their existing downsampling limit. Alphanumeric names such as `A2B`
remain a single reading unit on both platforms.

With local contextual meanings enabled, an isolated cached noun cannot appear
before the sentence model has answered. The focused meaning and subsequent
word rows are streamed only after a complete, validated line arrives. A queued
obsolete request is canceled; an already-sent focused request drains into the
bounded cache. Remaining sentence batches stop when its owner is gone, and
partial sentence answers are reusable on the next focus. Ordinary dictionary
translation remains the fallback when context is unavailable, labelled
`Dictionary`; contextual answers are labelled `In context`.

The reported `Får du undervisning om dagen eller om aftenen hos A2B?` fixture
returned `receives`; a sheep sentence retained `sheep`. On the development PC,
one warm-model sample produced the meaning in 286 ms and the complete explanation
in 787 ms. Cold loading in that run took 24.4 seconds. These are model-only fixture
measurements, excluding OCR, capture, pointer scheduling and actual desktop use.
The 14-pixel OCR fixture previously returned `A28`; the supersampled path returns
`A2B`. Neither this fixture nor the screenshots establish overall OCR parity with
Apple Vision across all fonts, colours and displays.
