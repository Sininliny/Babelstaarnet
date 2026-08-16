## Babelstårnet 0.5.1

The app opens from your Applications folder now, and this release is mostly an
apology for the instructions that said it would.

Every earlier download told you to Control-click **Babelstaarnet.app** and
choose **Open**. Apple removed that in macOS 15, and Babelstårnet requires
macOS 15 — so that instruction has never worked for anyone who has ever
downloaded this app. What replaced it is a button in **System Settings →
Privacy & Security** marked **Open Anyway**, and nothing here said so.

The archive now carries an installer. Extract the ZIP, double-click
**Install Babelstaarnet.command**, and click **Open** when Terminal asks about
a script downloaded from the Internet: it puts the app in **Applications**,
opens it, and tells you when it is done. It is plain text and says at the top
exactly what it does, so you can read it before you run it — and if you would
rather not run it at all, `Start Here.txt` ships beside it with the four clicks
that do the same thing by hand.

None of this was ever wrong with the app. Babelstårnet is signed, and macOS
checks that signature on every launch; what it is not is *notarized*, which
needs a paid Apple Developer Program membership this project does not have.
The warning is macOS reporting that missing membership. The installer clears
the flag your browser attaches to downloads, and nothing else.

Also in this release:

- `make install` builds the app and puts it straight into **Applications**. A
  bundle built on your own Mac was never downloaded, so it is never flagged and
  opens with no warning at any point. It quits a running copy first, since a
  bundle cannot be replaced under a process still executing out of it.
- The installer verifies the app's signature before it clears anything, and
  again after the copy, so a download that no longer matches itself is refused
  rather than installed.
- The download is a folder rather than a bare app, and is named `-macOS.zip`
  rather than `-macOS.app.zip` to say so.
- `--deep` is gone from the signing step. Nothing in the bundle is nested code
  for it to reach, and Apple does not recommend it for signing.
- The developer documentation now states what the ad-hoc signature does and
  does not buy, and why the designated-requirement override that keeps Screen
  Recording grants alive across rebuilds should not survive notarization.

### Download

**ZIP** — `Babelstaarnet.app`, `Install Babelstaarnet.command`, and
`Start Here.txt`. There is no DMG: a disk image is the right shape for an app
that opens with a double click, and this one does not, so it only added a mount
step in front of the same warning.

Extract it and double-click **Install Babelstaarnet.command**. To install by
hand instead: drag the app to **Applications**, double-click it, click **Done**
on the warning, then open **System Settings → Privacy & Security** and click
**Open Anyway** on the line about Babelstaarnet. Once only, either way.

All OCR, translation, explanations, speech, and learning-profile data are
processed and stored on your own Mac.
