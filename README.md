<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/logo-dark.png">
    <img src="docs/images/logo.png" alt="" width="88">
  </picture>
</p>

<h1 align="center">Babelstårnet</h1>

<p align="center"><strong>Hover any Danish word. Get the meaning. Keep reading.</strong></p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/hover-dark.png">
    <img src="docs/images/hover-light.png" alt="A Danish line on a page, with the meaning of the pointed-at word above it and the whole line below it in Danish word order, English standing in only for the words the reader cannot read yet." width="880">
  </picture>
</p>

<p align="center"><sub>Rendered from the app's own interface constants.</sub></p>

Babelstårnet is a local-first macOS translator for Danish. Point at a word
anywhere on screen — a website, a PDF, a form, text inside an image — and its
meaning appears where you are already looking. Nothing to select, paste, or
submit.

## The idea

**Danish carries the sentence; English fills only the gaps.** Word order and
grammar stay Danish, and so does every word you can already read. Only the words
you cannot read are swapped for English, in place — so you get one line to read
rather than two texts to reconcile.

**Which words those are is learned, not asked.** The app remembers what keeps
coming back to you, and hands each word back in Danish as you learn it. That is
the only progress signal there is: no lessons, no score, nothing to answer.

**Nothing leaves your Mac.** No screenshot, recognized text, definition, or audio
is sent to a remote service.

## Install

Requires macOS 15 or newer. Download the latest ZIP from
[Releases](https://github.com/Sininliny/Babelstaarnet/releases) and open it.

Double-click **Install Babelstaarnet.command** in the folder it makes. Terminal
asks whether you are sure you want to open a script downloaded from the
Internet; click **Open**. It puts the app in **Applications**, starts it, and
tells you when it is done. The installer is plain text, and says at the top
exactly what it does — three lines of it do the work.

Then, in the app:

1. Click **Set up Babelstårnet**. It has no Dock icon; look in the menu bar.
2. Enable Babelstårnet in the System Settings page that opens — it needs Screen
   Recording permission to read what is on screen.
3. Relaunch the app if macOS asks.
4. Click **Start translating**, or press `Fn+Z`.

No account and no engine installation required.

### Installing it by hand instead

Drag **Babelstaarnet.app** to **Applications** and double-click it. macOS says
it cannot verify the developer and offers only **Move to Trash** or **Done**;
click **Done**, open **System Settings → Privacy & Security**, scroll to the
line about Babelstaarnet being blocked, and click **Open Anyway**. Once only.

That button is the whole difference the installer makes. Up to macOS 14 you
could Control-click the app and choose **Open**;
[Apple removed that in macOS 15](https://www.macrumors.com/2024/08/06/macos-sequoia-gatekeeper-security-change/),
and this app requires macOS 15 — so if you have read that instruction anywhere
about this app, including in its own older releases, it no longer works.

The app **is** signed, ad-hoc: a signature macOS checks for damage on every
launch, and the one this project can produce. What it is not is *notarized*,
which needs a paid Apple Developer Program membership. macOS is reporting that
missing membership, not a finding about the app. Building from source has none
of this in the way — a bundle you built was never downloaded, so it is never
flagged, and `make install` puts it straight into **Applications**.

## Use

Press `Fn+Z` to start reading, and again to stop. Hover a Danish word: its
meaning appears above the pointer, and the whole line below it.

| Key | Does |
| --- | --- |
| `1` | Mark the word **known** |
| `2` | Mark it **unknown** and show more English |
| `3` | Pin the bubbles |

You never have to press any of them. Hold Option to keep a bubble open while you
move the pointer to it; every shortcut is editable under **Settings →
Shortcuts**.

---

**[How it works →](docs/HOW_IT_WORKS.md)** — the recognition pipeline, the design
rules behind the bubbles, building from source, and the optional open-source
engines.

“Babelstårnet” is Danish for “the Tower of Babel.” The repository keeps the ASCII
spelling `Babelstaarnet`.
