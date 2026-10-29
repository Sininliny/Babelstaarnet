"""Language routes and package ownership; no network, models or desktop access."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
from unittest.mock import patch
import zipfile

root = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("language_support", root / "Resources/LocalEngines/language_support.py")
support = importlib.util.module_from_spec(spec)
spec.loader.exec_module(support)
vectors = json.loads((root / "Tests/Shared/reading-contract.json").read_text(encoding="utf-8"))

class Converter:
    def __init__(self, kind): self.kind = kind
    def convert(self, text):
        return text.replace("书", "書").replace("读", "讀") if self.kind == "s2t" else text.replace("書", "书").replace("讀", "读")

for item in vectors["languagePairs"]:
    assert [a + "-" + b for a, b in support.route(item["source"], item["target"])] == item["models"]
    visited = []
    class Model:
        def __init__(self, a, b): self.edge = a + "-" + b
        def translate(self, texts): visited.append((self.edge, list(texts))); return list(texts)
    translator = support.RouteTranslator(item["source"], item["target"], Model, Converter)
    result = translator.translate(["讀书", "", "two sentences. Another."])
    assert [edge for edge, _ in visited] == item["models"]
    assert len(result) == 3 and result[1] == ""
    if item["target"] == "zh-Hans": assert "書" not in result[0] and "讀" not in result[0]
    if item["target"] == "zh-Hant": assert "书" not in result[0] and "读" not in result[0]
    if item["source"].startswith("zh") and visited: assert "讀" not in visited[0][1][0]

(root / "build").mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix="babel-languages-", dir=root / "build") as directory:
    folder = Path(directory)
    for name in ["../outside", "/outside", "C:/outside", "..\\outside"]:
        archive = folder / "bad.zip"
        with zipfile.ZipFile(archive, "w") as zipped:
            entry = zipfile.ZipInfo("safe"); entry.filename = name
            zipped.writestr(entry, "invalid")
            zipped.writestr("model/metadata.json", json.dumps(dict(from_code="da", to_code="en")))
        try: support.validate_model(archive, "da", "en")
        except ValueError: pass
        else: raise AssertionError("Unsafe archive accepted: " + name)
    archive = folder / "good.zip"
    with zipfile.ZipFile(archive, "w") as zipped:
        zipped.writestr("model/metadata.json", json.dumps(dict(from_code="da", to_code="en")))
    support.validate_model(archive, "da", "en")
    try: support.validate_model(archive, "en", "da")
    except ValueError: pass
    else: raise AssertionError("Wrong language model accepted")

    models_root = folder / "Argos/data/argos-translate/packages"
    models = []
    for a, b in [("da", "en"), ("en", "zh"), ("en", "da")]:
        path = models_root / (a + "-" + b); path.mkdir(parents=True)
        models.append(SimpleNamespace(from_code=a, to_code=b, package_path=path))
    registry = {"da--zh-Hans": ["da-en", "en-zh"], "en--zh-Hant": ["en-zh"]}
    support.save_recipes(folder, registry)
    (folder / "LanguageSupport/owned-models.json").write_text('["da-en", "en-zh"]', encoding="utf-8")
    with patch.object(support, "installed_models", return_value=models), patch.object(support, "status", return_value={}):
        support.remove(folder, "da", "zh-Hans", "da", "en")
        assert models[0].package_path.exists(), "Active route dependency removed"
        assert models[1].package_path.exists(), "Shared dependency removed"
        assert models[2].package_path.exists(), "Pre-existing model removed"
        support.remove(folder, "en", "zh-Hant")
        assert not models[1].package_path.exists(), "Unreferenced managed model not removed"
        assert models[2].package_path.exists()
    outside = folder / "unmanaged"; outside.mkdir()
    support.save_recipes(folder, {"da--en": ["da-en"]})
    with patch.object(support, "installed_models", return_value=[SimpleNamespace(from_code="da", to_code="en", package_path=outside)]):
        try: support.remove(folder, "da", "en")
        except ValueError: pass
        else: raise AssertionError("Removal escaped the managed model directory")
    assert outside.exists()

print("All 12 language routes, script conversion, archive validation and shared model ownership passed offline.")
