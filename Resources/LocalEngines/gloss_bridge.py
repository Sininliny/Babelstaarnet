#!/usr/bin/env python3
"""JSON bridge between Babelstårnet and a local language model, for glosses
that depend on the sentence a word is in.

Argos is asked one word at a time, and one word is not enough to translate: on
its own "får" is "sheep", "lide" is "suffer", "tag" is "roof". Given the
sentence, a language model answers with the sense the word has there, which is
the only sense the reader needed.

The model is loaded from a directory on disk and never by name, and every
Hugging Face switch that could reach the network is turned off before anything
that reads them is imported. The worker is handed the text being read; it has
no business holding a connection while it does.
"""

from __future__ import annotations

import os

# Before any import that consults them, and not merely defaulted: a value
# inherited from the environment must not be able to turn the network back on.
os.environ["HF_HUB_OFFLINE"] = "1"
os.environ["TRANSFORMERS_OFFLINE"] = "1"
os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"
os.environ["HF_DATASETS_OFFLINE"] = "1"

import argparse
import copy
import json
import re
import sys

# How many words one generated sequence glosses. The words of a sentence are
# split into chunks of this size and generated side by side in one batch:
# decoding is bound by memory bandwidth, so four sequences cost little more per
# step than one, and a 23-word sentence took 1.3 s instead of 3.5 s.
CHUNK_SIZE = 6
MAX_WORDS = 64
MAX_SENTENCE_CHARACTERS = 600
MAX_GLOSS_CHARACTERS = 48
MAX_EXPLANATION_CHARACTERS = 220

# The instructions, the labels, and the sentence the readiness check asks
# about all arrive from the app as `--prompts`: they belong to the language
# pack, and this worker names no language.
PROMPT_KEYS = (
    "gloss_instructions",
    "explain_instructions",
    "sentence_label",
    "words_label",
    "answer_label",
    "lemma_label",
    "explanation_label",
    "check_sentence",
    "check_word",
)


class Glosser:
    def __init__(self, model_directory: str, prompts: dict) -> None:
        from mlx_lm import load
        from mlx_lm.sample_utils import make_sampler

        if not os.path.isdir(model_directory):
            raise FileNotFoundError(f"No model at {model_directory}")
        self.prompts = prompts
        self.model, self.tokenizer = load(model_directory)
        self.sampler = make_sampler(temp=0.0)
        self.gloss_prefix, self.gloss_suffix = self._prefix(
            prompts["gloss_instructions"]
        )
        self.explain_prefix, self.explain_suffix = self._prefix(
            prompts["explain_instructions"]
        )

    def _prefix(self, instructions: str):
        """The part of every prompt that does not change, computed once.

        The chat template is filled with a marker where the request goes and
        split there. Everything before it is run through the model once and
        kept, so a request pays only for its own sentence.
        """
        from mlx_lm import stream_generate
        from mlx_lm.models.cache import make_prompt_cache, trim_prompt_cache

        marker = "@@REQUEST@@"
        template = self.tokenizer.apply_chat_template(
            [
                {"role": "system", "content": instructions},
                {"role": "user", "content": marker},
            ],
            add_generation_prompt=True,
            tokenize=False,
        )
        prefix, suffix = template.split(marker)
        cache = make_prompt_cache(self.model)
        tokens = self.tokenizer.encode(prefix, add_special_tokens=False)
        for _ in stream_generate(
            self.model,
            self.tokenizer,
            tokens,
            max_tokens=1,
            sampler=self.sampler,
            prompt_cache=cache,
        ):
            break
        # Generating one token to fill the cache also stored that token.
        trim_prompt_cache(cache, 1)
        return cache, suffix

    def _prompt(self, sentence: str, words: list[str], suffix: str) -> list[int]:
        listing = "\n".join(f"{index + 1}. {word}" for index, word in enumerate(words))
        prompts = self.prompts
        return self.tokenizer.encode(
            f"{prompts['sentence_label']}: {sentence}\n"
            f"{prompts['words_label']}:\n{listing}\n"
            f"{prompts['answer_label']}:{suffix}",
            add_special_tokens=False,
        )

    def gloss(self, sentence: str, words: list[str], focus: str | None) -> dict:
        import importlib

        batch_generate = importlib.import_module("mlx_lm.generate").batch_generate

        sentence = sentence[:MAX_SENTENCE_CHARACTERS]
        # The app reads one answer per word it asked about. Words past the
        # limit are answered with nothing rather than dropped, since a shorter
        # list than the one sent is an answer the app cannot line up.
        asked = len(words)
        words = words[:MAX_WORDS]
        chunks = [
            words[start : start + CHUNK_SIZE]
            for start in range(0, len(words), CHUNK_SIZE)
        ]
        prompts: list[list[int]] = []
        caches = []
        limits: list[int] = []
        if focus:
            prompts.append(self._prompt(sentence, [focus], self.explain_suffix))
            caches.append(copy.deepcopy(self.explain_prefix))
            limits.append(96)
        for chunk in chunks:
            prompts.append(self._prompt(sentence, chunk, self.gloss_suffix))
            caches.append(copy.deepcopy(self.gloss_prefix))
            limits.append(14 * len(chunk) + 20)
        if not prompts:
            return {"glosses": [""] * asked, "focus": None}

        texts = batch_generate(
            self.model,
            self.tokenizer,
            prompts,
            prompt_caches=caches,
            max_tokens=limits,
            sampler=self.sampler,
        ).texts

        answer = (
            parse_explanation(texts.pop(0), focus, self.prompts) if focus else None
        )
        glosses: list[str] = []
        for chunk, text in zip(chunks, texts):
            glosses.extend(parse_glosses(text, chunk))
        glosses.extend([""] * (asked - len(glosses)))
        return {"glosses": glosses, "focus": answer}


def fold(text: str) -> str:
    return re.sub(r"[^\wæøå-]", "", text.lower())


def clean(text: str, limit: int) -> str:
    text = re.sub(r"\s+", " ", text).strip().strip("`\"'“”‘’*")
    text = text.rstrip(".;,")
    return text if 0 < len(text) <= limit else ""


def parse_glosses(text: str, words: list[str]) -> list[str]:
    """One gloss per requested word, empty wherever the answer was unusable.

    A line is accepted only when its number is in range and the word it echoes
    is the word that number asked about. A gloss attached to the wrong word is
    worse than none: the reader would see a confident English word standing in
    for a Danish one it does not translate.
    """
    glosses = [""] * len(words)
    for line in text.splitlines():
        match = re.match(r"\s*(\d+)[.)]\s*(.+?)\s*$", line)
        if not match:
            continue
        index = int(match.group(1)) - 1
        if not 0 <= index < len(words) or glosses[index]:
            continue
        body = match.group(2)
        if "=" in body:
            echoed, _, gloss = body.partition("=")
            if fold(echoed) and fold(echoed) != fold(words[index]):
                continue
        else:
            gloss = body
        glosses[index] = clean(gloss, MAX_GLOSS_CHARACTERS)
    return glosses


def labelled(text: str, label: str):
    return re.search(rf"(?im)^\s*{re.escape(label)}\s*:\s*(.+)$", text)


def parse_explanation(text: str, focus: str, prompts: dict) -> dict:
    gloss = parse_glosses(text, [focus])[0]
    lemma = labelled(text, prompts["lemma_label"])
    found = labelled(text, prompts["explanation_label"])
    explanation = clean(found.group(1), MAX_EXPLANATION_CHARACTERS) if found else ""
    if explanation and explanation[-1] not in ".!?":
        explanation += "."
    return {
        "gloss": gloss,
        "lemma": clean(lemma.group(1), MAX_GLOSS_CHARACTERS) if lemma else "",
        "explanation": explanation,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--prompts", required=True)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--server", action="store_true")
    arguments = parser.parse_args()

    try:
        prompts = json.loads(arguments.prompts)
        missing = [key for key in PROMPT_KEYS if not prompts.get(key)]
        if missing:
            print(f"Prompts are missing {', '.join(missing)}", file=sys.stderr)
            return 14
        glosser = Glosser(arguments.model, prompts)

        if arguments.check:
            word = prompts["check_word"]
            answer = glosser.gloss(prompts["check_sentence"], [word], word)
            if not answer["glosses"] or not answer["glosses"][0]:
                print("The model loaded but returned no gloss", file=sys.stderr)
                return 13
            print("ready")
            return 0

        if arguments.server:
            for line in sys.stdin:
                if not line.strip():
                    continue
                # One request that cannot be answered is answered with its
                # error. Raised, it ended the worker, and the app paid seconds
                # reloading the model and then gave up on it for the session.
                try:
                    request = json.loads(line)
                    sentence = str(request.get("sentence", ""))
                    words = [str(word) for word in request.get("words", [])]
                    focus = request.get("focus")
                    answer = glosser.gloss(
                        sentence, words, str(focus) if focus else None
                    )
                except Exception as error:
                    answer = {"error": str(error) or type(error).__name__}
                print(json.dumps(answer, ensure_ascii=False), flush=True)
            return 0

        parser.error("Choose --check or --server")
    except ModuleNotFoundError:
        print("The mlx-lm Python package is not installed", file=sys.stderr)
        return 10
    except FileNotFoundError as error:
        print(str(error), file=sys.stderr)
        return 11
    except Exception as error:
        print(str(error), file=sys.stderr)
        return 12


if __name__ == "__main__":
    raise SystemExit(main())
