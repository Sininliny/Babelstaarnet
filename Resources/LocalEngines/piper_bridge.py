#!/usr/bin/env python3
"""Offline Danish Piper worker. Network access exists only in --install."""
from __future__ import annotations
import argparse
import base64
import hashlib
import io
import json
from pathlib import Path
import sys
import wave

VOICE = "da_DK-talesyntese-medium"
BASE = "https://huggingface.co/rhasspy/piper-voices/resolve/main/da/da_DK/talesyntese/medium/"
MODEL_SHA256 = "b9271efd25f7b8494bbd28d48dd675c8c119daa284f3ee488008935f515f1241"
CONFIG_SHA256 = "89fe13bd251406cc0088570d103ea7ac35823211d8466faf913268ab8506f41b"
HASHES = {VOICE + ".onnx": MODEL_SHA256, VOICE + ".onnx.json": CONFIG_SHA256}


def install(directory: Path) -> None:
    import urllib.request
    directory.mkdir(parents=True, exist_ok=True)
    for name in (VOICE + ".onnx", VOICE + ".onnx.json", "MODEL_CARD"):
        path = directory / name
        if path.exists() and (name not in HASHES or hashlib.sha256(path.read_bytes()).hexdigest() == HASHES[name]):
            continue
        temporary = path.with_name(path.name + ".download")
        with urllib.request.urlopen(BASE + name, timeout=120) as response, temporary.open("wb") as output:
            while chunk := response.read(1024 * 1024):
                output.write(chunk)
        if name in HASHES and hashlib.sha256(temporary.read_bytes()).hexdigest() != HASHES[name]:
            raise ValueError("Danish voice checksum mismatch; refusing to install")
        temporary.replace(path)
    checked_config(directory)


def checked_config(directory: Path) -> dict:
    config = json.loads((directory / (VOICE + ".onnx.json")).read_text(encoding="utf-8"))
    if config.get("language", {}).get("code") != "da_DK" or config.get("espeak", {}).get("voice") != "da":
        raise ValueError("The voice and phonemizer must both be Danish (da_DK / da)")
    return config


class DanishVoice:
    def __init__(self, directory: Path):
        import onnxruntime
        from piper import PiperVoice
        from piper.config import PiperConfig
        config = checked_config(directory)
        onnxruntime.disable_telemetry_events()
        options = onnxruntime.SessionOptions()
        options.intra_op_num_threads = 2
        options.inter_op_num_threads = 1
        self.voice = PiperVoice(config=PiperConfig.from_dict(config), session=onnxruntime.InferenceSession(
            str(directory / (VOICE + ".onnx")), sess_options=options, providers=["CPUExecutionProvider"]))

    def synthesize(self, text: str) -> bytes:
        text = text.strip()
        if not text or len(text) > 400:
            raise ValueError("Speech input must contain 1–400 characters")
        buffer = io.BytesIO()
        with wave.open(buffer, "wb") as output:
            self.voice.synthesize_wav(text, output)
        return buffer.getvalue()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-directory", type=Path, required=True)
    parser.add_argument("--install", action="store_true")
    parser.add_argument("--sample", type=Path)
    parser.add_argument("--text", default="Jeg spiser æbler. Det er en anspændt situation, men vi finder en løsning.")
    args = parser.parse_args()
    if args.install:
        install(args.model_directory)
        print("Danish neural voice installed and verified")
        return 0
    voice = DanishVoice(args.model_directory)
    if args.sample:
        args.sample.write_bytes(voice.synthesize(args.text))
        print("Danish audio saved")
        return 0
    for line in sys.stdin:
        if not line.strip():
            continue
        request = json.loads(line)
        audio = voice.synthesize(request.get("text", "æbler"))
        print(json.dumps({"audio": base64.b64encode(audio).decode("ascii"), "voice": VOICE,
                          "language": "da-DK", "sample_rate": voice.voice.config.sample_rate}), flush=True)
    return 0

if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
