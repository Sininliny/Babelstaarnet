#!/usr/bin/env python3
"""Local language routes and explicit setup. Runtime never downloads resources."""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import sys
import zipfile


def catalog():
    here = Path(__file__).resolve().parent
    for path in (here / "language-catalog.json", here.parent / "LanguagePacks" / "catalog.json"):
        if path.is_file():
            return json.loads(path.read_text(encoding="utf-8"))
    raise RuntimeError("The bundled language catalog is missing")


def language(identifier):
    identifier = {"zh": "zh-Hans", "zt": "zh-Hant"}.get(identifier, identifier)
    return next(item for item in catalog()["languages"] if item["id"] == identifier)


def route(source, target):
    a, b = language(source)["engineCode"], language(target)["engineCode"]
    if a == b:
        return []
    return [(a, b)] if "en" in (a, b) else [(a, "en"), ("en", b)]


class RouteTranslator:
    def __init__(self, source, target, factory, converter_factory=None):
        self.source, self.target = language(source), language(target)
        self.to_simple = self.to_traditional = None
        if self.source["cjk"] or self.target["cjk"]:
            if converter_factory is None:
                from opencc import OpenCC
                converter_factory = OpenCC
            self.to_simple, self.to_traditional = converter_factory("t2s"), converter_factory("s2t")
        self.models = [factory(a, b) for a, b in route(source, target)]

    def translate(self, texts):
        values = list(texts)
        if self.source["cjk"]:
            values = [self.to_simple.convert(t) for t in values]
        for model in self.models:
            values = model.translate(values)
        if self.target["cjk"]:
            converter = self.to_traditional if self.target["id"] == "zh-Hant" else self.to_simple
            values = [converter.convert(t) for t in values]
        return values


def configure(directory):
    root = Path(directory).expanduser().resolve()
    os.environ["XDG_DATA_HOME"] = str(root / "Argos" / "data")
    os.environ["XDG_CONFIG_HOME"] = str(root / "Argos" / "config")
    os.environ["XDG_CACHE_HOME"] = str(root / "Argos" / "cache")
    os.environ["ARGOS_PACKAGES_DIR"] = str(root / "Argos" / "data" / "argos-translate" / "packages")
    os.environ["ARGOS_DEVICE_TYPE"] = "cpu"
    os.environ["ARGOS_CHUNK_TYPE"] = "MINISBD"
    return root


def recipes(root):
    path = root / "LanguageSupport" / "installed.json"
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def save_recipes(root, value):
    path = root / "LanguageSupport" / "installed.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")
    temporary.replace(path)


def installed_models():
    if importlib.util.find_spec("argostranslate") is None:
        return []
    from argostranslate import package
    return [p for p in package.get_installed_packages() if p.type == "translate"]


def status(root):
    installed = {f"{p.from_code}-{p.to_code}": p for p in installed_models()}
    conversion = importlib.util.find_spec("opencc") is not None
    pairs = []
    for source in catalog()["languages"]:
        for target in catalog()["languages"]:
            if source["id"] == target["id"]:
                continue
            edges = [f"{a}-{b}" for a, b in route(source["id"], target["id"])]
            needs_conversion = source["cjk"] or target["cjk"]
            pairs.append(dict(source=source["id"], target=target["id"], models=edges,
                              conversion=needs_conversion, ready=all(e in installed for e in edges) and (not needs_conversion or conversion)))
    return dict(runtime=importlib.util.find_spec("argostranslate") is not None,
                conversion=conversion, models=list(installed), pairs=pairs, installed=list(recipes(root)))


def validate_model(path, source, target):
    with zipfile.ZipFile(path) as archive:
        size = 0
        for item in archive.infolist():
            name = PurePosixPath(item.filename)
            if not name.parts or name.is_absolute() or ".." in name.parts or "\\" in item.filename or ":" in name.parts[0] or (item.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError("Unsafe model archive")
            size += item.file_size
        if size > 4_000_000_000:
            raise ValueError("Model archive is too large")
        metadata = [n for n in archive.namelist() if n.endswith("/metadata.json") or n == "metadata.json"]
        if len(metadata) != 1:
            raise ValueError("Model metadata is missing")
        if archive.getinfo(metadata[0]).file_size > 65536:
            raise ValueError("Model metadata is too large")
        data = json.loads(archive.read(metadata[0]))
        if data.get("from_code") != source or data.get("to_code") != target or data.get("type", "translate") != "translate":
            raise ValueError("The downloaded model does not match the requested direction")


def install(root, source, target):
    # Only the explicit setup command reaches the package index or downloads.
    expected = route(source, target)
    if expected:
        from argostranslate import package
    current = {(p.from_code, p.to_code) for p in installed_models()}
    ownership_file = root / "LanguageSupport" / "owned-models.json"
    try:
        owned = set(json.loads(ownership_file.read_text(encoding="utf-8")))
    except (OSError, ValueError):
        owned = set()
    missing = [edge for edge in expected if edge not in current]
    if missing:
        package.update_package_index()
        available = package.get_available_packages()
        for index, (a, b) in enumerate(missing):
            print(json.dumps(dict(progress=index / len(missing), stage=f"Installing {a} → {b}")), flush=True)
            candidate = next((p for p in available if p.from_code == a and p.to_code == b), None)
            if candidate is None:
                raise RuntimeError(f"No offline {a} → {b} model is available in the package index")
            archive = candidate.download()
            validate_model(archive, a, b)
            package.install_from_path(archive)
            owned.add(a + "-" + b)
            ownership_file.parent.mkdir(parents=True, exist_ok=True)
            ownership_file.write_text(json.dumps(sorted(owned)), encoding="utf-8")
    registry = recipes(root)
    registry[source + "--" + target] = [f"{a}-{b}" for a, b in expected]
    save_recipes(root, registry)
    return status(root)


def remove(root, source, target, keep_source=None, keep_target=None):
    registry = recipes(root)
    key = source + "--" + target
    # Pre-existing models are preserved until explicitly adopted by setup.
    owned = registry.pop(key, [])
    required = {edge for recipe in registry.values() for edge in recipe}
    if keep_source and keep_target and key != keep_source + "--" + keep_target:
        required.update(f"{a}-{b}" for a, b in route(keep_source, keep_target))
    ownership_file = root / "LanguageSupport" / "owned-models.json"
    try:
        managed = set(json.loads(ownership_file.read_text(encoding="utf-8")))
    except (OSError, ValueError):
        managed = set()
    models_root = (root / "Argos" / "data" / "argos-translate" / "packages").resolve()
    for model in installed_models():
        edge = f"{model.from_code}-{model.to_code}"
        if edge in owned and edge in managed and edge not in required:
            path = Path(model.package_path).resolve()
            if not path.is_relative_to(models_root) or path == models_root:
                raise ValueError("Refusing to remove a model outside this app's managed package directory")
            shutil.rmtree(path)
            managed.discard(edge)
    if ownership_file.exists():
        ownership_file.write_text(json.dumps(sorted(managed)), encoding="utf-8")
    save_recipes(root, registry)
    return status(root)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("operation", choices=["status", "install", "remove"])
    parser.add_argument("--data-directory", required=True)
    parser.add_argument("--source", default="da")
    parser.add_argument("--target", default="en")
    parser.add_argument("--keep-source")
    parser.add_argument("--keep-target")
    args = parser.parse_args()
    language(args.source); language(args.target)
    root = configure(args.data_directory)
    result = status(root) if args.operation == "status" else install(root, args.source, args.target) if args.operation == "install" else remove(root, args.source, args.target, args.keep_source, args.keep_target)
    print(json.dumps(dict(result=result), ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
