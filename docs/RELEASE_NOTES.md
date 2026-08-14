## Babelstårnet 0.4.0

Point at a Danish word and the bubble below now answers with the whole
sentence, gathered from however many wrapped lines it is printed across.

Apple's text recognition hands back one visual line at a time, and a line is
wherever the column happened to wrap. Bridging that line on its own produced
fragments — text beginning after the subject and stopping before the verb —
which taught neither the Danish word order the bridge exists to preserve nor
the meaning that was asked about. The lines above and below the pointer are now
joined until a real sentence stop is found, and only those lines are sent for
translation, so a sentence that fits on one line costs exactly what it did
before.

Finding that stop is the Danish-specific part. A period is a weak signal in the
language — `den 15. september`, `bl.a.`, `kl. 13`, `Circle U.'s` — so a stop
counts only when what follows opens a sentence, which in Danish means a
capital.

Also in this release:

- The word under the pointer is marked in the sentence below, on the English
  standing in for it when it was replaced. The two panels answer the same
  question and had nothing tying them together.
- Swapped words are set as running text: one baseline, one word space, and the
  faint tint marking them is drawn only while swaps are still the exception on
  the line, rather than highlighting a whole sentence of English.
- Bubble text sits on its own ground inside the panel material, for the
  ordinary hard case of a white article read under a system in dark appearance.
- Pointing at a word your profile already counts as known answers **Known**
  instead of an empty panel.
- Bubbles keep clear of every line the sentence is printed on, not just the
  line under the pointer.
- The whole-line translation control is gone, along with its shortcut. Asking
  for a whole line in English is asking for a translation rather than a bridge,
  and nothing in the app learned from the press.
- Which binaries the app will execute is decided in the app rather than by
  `$PATH`, in a process that hands its child a picture of the screen.

### Download

**APP ZIP** — a ZIP containing `Babelstaarnet.app`. There is no DMG: a disk
image is the right shape for an app that opens with a double click, and this
one cannot, so it only added a mount step in front of the same warning.

This preview is ad-hoc signed because the project does not have an Apple
Developer ID, and macOS will say it cannot verify the developer. After
extracting, Control-click **Babelstaarnet.app**, choose **Open**, and confirm
once.

All OCR, translation, explanations, speech, and learning-profile data are
processed and stored on your own Mac.
