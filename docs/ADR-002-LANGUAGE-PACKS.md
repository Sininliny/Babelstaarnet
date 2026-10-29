# ADR 002: Explicit language directions and local component packages

Status: accepted for 0.7.0.

## Problem and decision

Reading used one Danish→English pair. Simply changing labels would leave the
OCR language, curated meanings, contextual prompts and profiles pointing at
the old direction. Four stable IDs now describe the supported languages:
`da`, `en`, `zh-Hans`, `zh-Hant`. All twelve different-language directions are
selectable. App chrome remains English; choosing an assistance language changes
reading support, not the application's interface language.

`Resources/LanguagePacks/catalog.json` is the shared catalog for native clients
and the Python worker. Swift `LanguagePacks` composes source and target values;
Windows `ReadingLanguagePair` composes the corresponding portable data. Native
UI, capture, OCR dictionaries and speech remain platform adapters. Original
Danish tables/prompts still originate in `Sources/LanguageDanish/Danish.swift`.
Their English glosses are used only by the original Danish→English pair.

Argos/CTranslate2 supplies `da-en`, `en-da`, `en-zh`, `zh-en`. Danish↔Chinese
uses an explicit English pivot; its two stages can lose nuance, so the UI
labels the route. A script converter normalizes Chinese model input to
simplified Chinese and produces the selected output script. Simplified↔traditional
uses conversion alone, without loading translation models. Conversion is not a
claim to regional idiom or terminology localization.

## Setup and ownership

`language_support.py` has separate status, install and remove entry points.
Reading workers never update the package index or install anything. Opening
settings reads local status. Installation is an explicit internet action and
validates model direction and archive paths before extraction. The runtime and
model directories retain their existing locations, so an upgrade reuses models.
Python 3.10–3.13 must be available to create the private environment.

Installed directions register dependencies. Removal releases a direction and
only deletes app-managed models unused by other registered directions or the
currently active different direction. Pre-existing model installations are kept.
The small shared Python runtime and script converter remain installed when a
direction is removed. Learning data is never removed by language setup.

Windows installs the chosen source OCR capability through an explicit
administrator setup action. It delegates removal and optional speech voice
downloads to Windows Language options because these resources are shared with
other apps. macOS uses built-in Vision and installed offline voices; its existing
optional Tesseract installer remains available. Missing speech never falls back
to a voice in another language. Danish Piper is retained; other languages use
matching offline system voices.

## State and scope

Language changes use Apply & restart. This avoids replacing capture services or
reading workers while a hover request is in flight. Models are loaded only for
the active direction. Caches and Word Books are isolated by direction, and
profile export identifies its source language. Danish→English keeps its original
data paths and preference keys. Other pairs use `Profiles/<source>--<target>` or
the equivalent namespaced native preferences. Switching back restores that pair.

Both systems use native Chinese dictionary segmentation, preserve original
script/word ranges and accept full-width sentence punctuation without spaces.
Windows keeps the native segmenter out of its portable domain project.
DR news remains a Danish-source feature; other learning languages do not receive
Danish news cards. No new-language news sources or interface localization are
implied by adding a reading direction.

## Verification and alternatives

Shared vectors cover all twelve routes and Chinese sentence boundaries; native
checks cover pair persistence, glossary isolation, profile identity and Chinese
word ranges. Python checks inject engines/converters and verify dependency
retention and archive/path rejection without downloading models. These tests
prove routing and lifecycle behavior, not translation quality on unseen text.
New directions still need real-device reading and voice checks with installed
packs. Existing offline Danish engine checks protect the original path.

A monolithic all-language download was rejected because a script-only pair
needs no translation weights. An English-only target abstraction was rejected
because it would corrupt assistance-language output and cached meanings.
Automatic installation during reading was rejected to preserve offline runtime.

## Upstream references

- [Argos model index](https://github.com/argosopentech/argospm-index/blob/main/index.json)
- [OpenCC conversion configurations](https://github.com/BYVoid/OpenCC)
- [Pure Python converter used by setup](https://github.com/yichen0831/opencc-python)
- [Windows installed OCR language discovery](https://learn.microsoft.com/en-us/uwp/api/windows.media.ocr.ocrengine.availablerecognizerlanguages)
