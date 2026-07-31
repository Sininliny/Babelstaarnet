#!/usr/bin/env python3
"""Small JSON bridge between Babelstårnet and Argos Translate."""

from __future__ import annotations

import argparse
import json
import re
import sys


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


def install_package(source: str, target: str) -> None:
    import argostranslate.package

    if translation_for(source, target) is not None:
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
        candidates = [
            cleaned.replace(" ", "_"),
            *reversed(cleaned.split()),
        ]
        synsets = []
        for candidate in candidates:
            if not candidate:
                continue
            synsets = wordnet.synsets(candidate)
            if synsets:
                break

        if synsets:
            definition = synsets[0].definition().strip()
        elif cleaned:
            definition = f"a word or expression with the meaning “{cleaned}”"
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
    parser.add_argument("--check-wordwise", action="store_true")
    arguments = parser.parse_args()

    try:
        if arguments.install:
            install_package(arguments.source, arguments.target)
            print("installed")
            return 0

        translation = translation_for(arguments.source, arguments.target)
        if translation is None:
            print(
                f"Argos language package {arguments.source} → "
                f"{arguments.target} is not installed",
                file=sys.stderr,
            )
            return 11

        if arguments.check:
            print("ready")
            return 0

        if arguments.check_wordwise:
            english_definitions([])
            print("ready")
            return 0

        if arguments.batch:
            request = json.load(sys.stdin)
            texts = request.get("texts", [])
            translations = [translation.translate(text) for text in texts]
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
                translations = [translation.translate(text) for text in texts]
                print(
                    json.dumps(
                        {"translations": translations},
                        ensure_ascii=False,
                    ),
                    flush=True,
                )
            return 0

        parser.error("Choose --check, --install, --batch, or --server")
    except ModuleNotFoundError:
        print("The argostranslate Python package is not installed", file=sys.stderr)
        return 10
    except Exception as error:
        print(str(error), file=sys.stderr)
        return 12


if __name__ == "__main__":
    raise SystemExit(main())
