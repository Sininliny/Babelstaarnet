#!/usr/bin/env python3
"""Small JSON bridge between Babelstårnet and Argos Translate."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

# -I excludes cwd and even the script directory. Only add our bundled sibling
# directory, never a caller-controlled working directory or PYTHONPATH.
sys.path.insert(0, str(Path(__file__).resolve().parent))


class WordTranslator:
    """Use the installed Argos model directly for already-separated hover text.

    The Windows reader supplies individual words (or one OCR line), so loading
    SpaCy, PyTorch, Stanza and a sentence detector adds no useful processing.
    Keep Argos' tokenizer and decoding settings, and batch independent words.
    The existing full server remains available to the macOS client.
    """

    def __init__(self, source: str, target: str):
        import ctranslate2
        from argostranslate import package, settings

        self.package = next(
            (item for item in package.get_installed_packages()
             if item.type == "translate" and item.from_code == source and item.to_code == target),
            None,
        )
        if self.package is None:
            raise RuntimeError(f"Argos language package {source} → {target} is not installed")
        self.settings = settings
        self.model = ctranslate2.Translator(
            str(self.package.package_path / "model"), device="cpu",
            inter_threads=settings.inter_threads, intra_threads=settings.intra_threads,
            compute_type=settings.compute_type,
        )

    def translate(self, texts: list[str]) -> list[str]:
        values = [""] * len(texts)
        nonempty = [(index, text.strip()) for index, text in enumerate(texts) if text.strip()]
        if not nonempty:
            return values
        tokenized = [self.package.tokenizer.encode(text) for _, text in nonempty]
        prefix = self.package.target_prefix
        results = self.model.translate_batch(
            tokenized, target_prefix=[[prefix]] * len(tokenized) if prefix else None,
            replace_unknowns=True, max_batch_size=self.settings.batch_size,
            batch_type="tokens", beam_size=max(1, self.settings.beam_size),
            num_hypotheses=1, length_penalty=0.2,
        )
        for (index, _), result in zip(nonempty, results):
            value = self.package.tokenizer.decode(result.hypotheses[0])
            if prefix and value.startswith(prefix):
                value = value[len(prefix):]
            values[index] = value.lstrip(" ")
        return values


def word_server(source: str, target: str) -> int:
    from language_support import RouteTranslator
    translator = RouteTranslator(source, target, WordTranslator)
    for line in sys.stdin:
        if line.strip():
            request = json.loads(line)
            print(json.dumps({"translations": translator.translate(request.get("texts", []))},
                             ensure_ascii=False), flush=True)
    return 0


def translation_for(source: str, target: str):
    import argostranslate.translate

    languages = argostranslate.translate.get_installed_languages()
    source_language = next((item for item in languages if item.code == source), None)
    target_language = next((item for item in languages if item.code == target), None)
    if source_language is None or target_language is None:
        return None
    try:
        return source_language.get_translation(target_language)
    except Exception:
        return None


def install_package(source: str, target: str, direct_only: bool = False) -> None:
    import argostranslate.package

    installed = (any(item.type == "translate" and item.from_code == source and item.to_code == target
                     for item in argostranslate.package.get_installed_packages())
                 if direct_only else translation_for(source, target) is not None)
    if installed:
        return

    argostranslate.package.update_package_index()
    packages = argostranslate.package.get_available_packages()
    package = next(
        (
            item
            for item in packages
            if item.from_code == source and item.to_code == target
        ),
        None,
    )
    if package is None:
        raise RuntimeError(f"No Argos package is available for {source} → {target}")
    argostranslate.package.install_from_path(package.download())


def english_definitions(words: list[str]) -> list[str]:
    from nltk.corpus import wordnet

    wordnet.ensure_loaded()
    definitions: list[str] = []
    for raw_word in words:
        cleaned = re.sub(r"[^A-Za-z' -]", "", raw_word).strip().lower()
        candidates = [cleaned.replace(" ", "_")]
        if " " not in cleaned:
            candidates.append(cleaned)
        synsets = []
        for candidate in candidates:
            if candidate:
                synsets = wordnet.synsets(candidate)
            if synsets:
                break
        if synsets:
            definition = synsets[0].definition().strip()
        elif cleaned:
            definition = f"a term used for {cleaned}"
        else:
            definition = "a word used in this sentence"
        definitions.append(definition[:240])
    return definitions


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", default="da")
    parser.add_argument("--target", default="en")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--install", action="store_true")
    parser.add_argument("--batch", action="store_true")
    parser.add_argument("--server", action="store_true")
    parser.add_argument("--word-server", action="store_true")
    parser.add_argument("--install-word-model", action="store_true")
    parser.add_argument("--check-word-model", action="store_true")
    parser.add_argument("--check-word-bridge", action="store_true")
    arguments = parser.parse_args()

    try:
        if arguments.install or arguments.install_word_model:
            install_package(arguments.source, arguments.target, direct_only=arguments.install_word_model)
            print("installed")
            return 0

        if arguments.word_server:
            return word_server(arguments.source, arguments.target)

        if arguments.check_word_model:
            from language_support import RouteTranslator, language
            RouteTranslator(arguments.source, arguments.target, WordTranslator).translate([language(arguments.source)["sample"]])
            print("ready")
            return 0

        from language_support import RouteTranslator
        translation = RouteTranslator(arguments.source, arguments.target, WordTranslator)

        if arguments.check:
            print("ready")
            return 0

        if arguments.check_word_bridge:
            english_definitions([])
            print("ready")
            return 0

        if arguments.batch:
            request = json.load(sys.stdin)
            texts = request.get("texts", [])
            translations = translation.translate(texts)
            json.dump(
                {"translations": translations},
                sys.stdout,
                ensure_ascii=False,
            )
            return 0

        if arguments.server:
            for line in sys.stdin:
                if not line.strip():
                    continue
                request = json.loads(line)
                if "define_words" in request:
                    texts = english_definitions(request.get("define_words", []))
                else:
                    texts = request.get("texts", [])
                translations = translation.translate(texts)
                print(
                    json.dumps(
                        {"translations": translations},
                        ensure_ascii=False,
                    ),
                    flush=True,
                )
            return 0

        parser.error("Choose --check, --install, --batch, or --server")
    except ModuleNotFoundError as error:
        print("Missing local language component: " + str(error.name) + ". Install this language pair in Settings.", file=sys.stderr)
        return 10
    except Exception as error:
        print(str(error), file=sys.stderr)
        return 12


if __name__ == "__main__":
    raise SystemExit(main())
