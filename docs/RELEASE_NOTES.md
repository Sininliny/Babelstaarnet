## Babelstårnet 0.5.0

The answer now arrives beside the word it is about, and says which word that
is.

Neither panel may cover the sentence being read, and a sentence running over
several lines counts as one block — so a word in the middle of a paragraph
cannot be answered beside itself. There was one fallback for that case, and it
reserved room above the paragraph for a sentence panel that then almost always
went below it instead, leaving the reserved space empty and pushing the answer
a whole panel further away than anything required. On a four-line paragraph in
a 1130-point column, a word on the third line was answered 266 points away
from itself. It is 54 now.

Which position is nearest is not a property of a fixed list — a word on the
last line is nearest the space under its block, one on the first line the space
over it, one at the edge of a column the margin beside it — so candidates are
ranked by measured clear space from the word, edge to edge.

That still leaves the reader to work out which of the words in front of them is
being answered, which is only obvious while the pointer has not moved, and the
eye leaves the pointer long before the hand does. The word is marked on the
page with the same accent rule the sentence panel already draws under it.

Also in this release:

- Bubble corners are drawn as one edge. The drop shadow was clipped by the
  panel it was drawn in and pooled in the corner notches as grey blur; the
  panel's ground and its material drew the same arc twice over the same pixels;
  and panels placed against text the OCR reported in fractions of a point
  landed off the display's pixel grid. The panels also have a real edge on a
  white page, which the old one — white at 28% — could not give them.
- A local OCR engine that exits before it has read the capture no longer takes
  the app down with it. Reachable by anyone with Tesseract installed and no
  Danish language data, and it falls back to Vision now.
- Carrying word identities between scans cost the product of the two scans:
  659 ms of main-actor time on an 840-word page, between a finished scan and
  the bubble. It is linear now, at 5.2 ms.
- The pointer is followed in one pass instead of three, and not followed at all
  while it is parked or while the page has no words on it. A page is keyed by
  the word rather than by each occurrence of it, so an explanation is prepared
  once however many times the word appears.
- Ending a reading session no longer leaves its page behind for the next one to
  open against.
- The app is split into capability modules over a shared core, with the
  language being read carried as a value rather than compiled into each
  service. Adding a language is a new target beside `LanguageDanish`; no
  capability module can name one.

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
