# Security and privacy

Babelstårnet reads the screen. That is the whole function, and it is also the
reason this page exists: an app with permission to see everything you look at
owes you a precise account of what it does with that, rather than a promise.

Last reviewed 14 August 2026, against version 0.3.0.

## The guarantee

**Nothing you read leaves your Mac.** No screenshot, recognized text,
translation, definition, or audio is transmitted anywhere.

This holds structurally rather than by policy: there is no networking code in
the application. No `URLSession`, no `NWConnection`, no socket, no HTTP client
anywhere under `Sources/`. The app cannot send your screen somewhere because it
contains nothing capable of sending anything. A grep is enough to check, and it
is worth more than this paragraph:

```sh
grep -rn "URLSession\|NWConnection\|dataTask\|https://" Sources/
```

Three consequences worth stating plainly:

- **Captures are never written to disk.** The cropped PNG goes to the OCR engine
  over a stdin pipe and is never given a filename. Nothing lands in a temporary
  directory for another process to read, and nothing survives a crash.
- **Nothing sensitive is logged.** The single logger records pipeline stage
  names and millisecond durations. Recognized text is never logged, so it never
  reaches the unified log, a sysdiagnose, or a crash report.
- **The translation worker is offline.** The Argos bridge only reaches the
  network under `--install`, when it downloads language models. The `--server`
  mode used for every translation makes no network calls at all.

### Where the network *is* used

Being accurate matters more than sounding absolute. Network access happens in
exactly two places, neither of which carries anything you read:

1. **Installing the optional open-source engines**, which downloads Tesseract,
   Python packages, and the Argos language models. You choose when this runs,
   and it is not required — the app works on Apple's frameworks alone.
2. **Apple's Translation framework**, on first use, may download a Danish
   language pack from Apple. Translation itself then runs on-device. Apple's
   Vision recognition and the speech synthesizer are on-device throughout.

## What is stored, and where

| What | Where | Contains |
| --- | --- | --- |
| Learning profile | `~/Library/Preferences/dev.sinin.babelstaarnet.plist` | Danish words, knowledge levels, counts, timestamps |
| Argos models and venv | `~/Library/Application Support/Babelstaarnet/` | Language models, Python environment |
| Exported profile | wherever you choose to save it | The learning profile, as JSON |

**The profile records words, not what you were reading.** Each entry keeps one
`lastContextSignature`, which exists to tell "met this word again somewhere new"
apart from "hovered the same line twice". It is a 64-bit FNV-1a hash of the
normalized line, not the line, so neither the stored profile nor an export
contains a sentence you read.

Two honest limits on that:

- The hash is not cryptographic. It cannot reveal text nobody has guessed, but
  someone holding your export could test a *specific* sentence and learn whether
  you had read it. Only the most recent context per word is kept.
- The profile is stored unencrypted, and the word list itself is mildly
  revealing — it is a record of which Danish words you struggled with. Any
  process running as you can read it, and it may be picked up by backup or sync
  tools that copy `~/Library/Preferences`.

Exports are written wherever you point the save panel, with ordinary file
permissions. Treat one as you would any personal document.

**Imports are treated as hostile.** A profile handed to you by someone else is
checked for size, record count, schema version, and language, and every record
is validated before anything is merged. Import cannot execute anything.

## What the app runs

The optional engines are separate programs, so the trust question is which
binary gets executed.

**Engines are resolved from a closed list of absolute paths**
(`Sources/Babelstaarnet/Services/InstalledEngineLocations.swift`). Until
14 August 2026 the resolvers also walked every directory in `$PATH`, which let
an environment variable decide what the app executed — a real risk for a process
that hands its child a picture of your screen. An engine installed somewhere
unusual is now not found rather than guessed at, and reading falls back to
Apple's Vision.

**Release builds load the installer and bridge scripts only from inside the
app bundle.** Both previously fell back to a path relative to the process's
working directory, which is a development convenience that had no business in a
shipped build; it is now compiled out except in debug builds.

Some paths the app will execute from are writable without an administrator
password — `/opt/homebrew/bin` and the managed Python environment under
Application Support both belong to your user account. This is inherent to how
Homebrew and virtual environments work, and it means malware already running as
you could replace an engine. It is a reason to care about what else you run, not
something this app can close.

## Known gaps

Recorded here rather than quietly carried:

- **Python dependencies are installed unpinned and unverified.** The installer
  runs `pip install --upgrade pip argostranslate nltk` with no version pins and
  no hashes, so a compromised release of those packages or their dependencies
  would execute as you. Pinning with `--require-hashes` is the fix.
- **The WordNet archive is downloaded without an integrity check**, from a
  moving branch, and extracted unverified. It should be pinned to a commit and
  checked against a known SHA-256.
- **The app is not sandboxed.** No entitlements file exists. Screen capture
  across all displays plus spawning engine subprocesses is difficult to reconcile
  with the App Sandbox, but the consequence should be stated: a compromise of
  this app has whatever file access your user account has. Signed builds do use
  the hardened runtime.

## Permissions the app asks for

Screen Recording, and nothing else. It is required to read text under the
pointer; macOS grants no narrower version of it. The app captures a small region
around the cursor rather than the whole display, and its own windows are excluded
from what it captures.

Revoke it at any time under **System Settings → Privacy & Security → Screen
Recording**. Reading stops immediately; the app does not degrade to some other
method.

## Reporting something

Open an issue at
<https://github.com/Sininliny/Babelstaarnet/issues>. If it is a vulnerability,
say so and leave out the details until it can be discussed privately.
