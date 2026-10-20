"""Compare hover inference with the installed full Argos reference, offline."""
import importlib.util
import json
import os
from pathlib import Path
import sys

bridge, data = Path(sys.argv[1]), Path(sys.argv[2])
for kind in ("data", "config", "cache"):
    os.environ[f"XDG_{kind.upper()}_HOME"] = str(data / "Argos" / kind)
os.environ["ARGOS_PACKAGES_DIR"] = str(data / "Argos" / "data" / "argos-translate" / "packages")
os.environ["ARGOS_CHUNK_TYPE"] = "MINISBD"
os.environ["ARGOS_DEVICE_TYPE"] = "cpu"
os.environ["ARGOS_MODEL_PROVIDER"] = "OPENNMT"
os.environ["ARGOS_INTER_THREADS"] = "1"
os.environ["ARGOS_INTRA_THREADS"] = "2"
spec = importlib.util.spec_from_file_location("argos_bridge", bridge)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
fast = module.WordTranslator("da", "en")
words = ["æbler", "smør", "mælk", "anspændte", "situationen", "alvorligt", "næsten",
         "mennesker", "regeringen", "beslutning", "arbejde", "læser", "studerende",
         "udvikling", "sundhed", "uddannelse", "oversættelse", "københavn", "blå",
         "gik", "gå", "går", "spørgsmål", "fødselsdag", "muligheder", "tilladelse",
         "ønsker", "hjem", "bog", "dag", "situation", "netværk"]
actual = fast.translate(words)
assert not any(name in sys.modules for name in ("torch", "spacy", "stanza", "minisbd")), \
    "Hover startup must not import unused sentence-processing libraries"
assert fast.translate(["", "   ", "æbler"]) == ["", "", actual[0]], \
    "Empty entries must retain their positions"
reference = module.translation_for("da", "en")
expected = [reference.translate(word) for word in words]
differences = [(word, old, new) for word, old, new in zip(words, expected, actual) if old != new]
assert not differences, f"Translation changed: {differences}"
print(json.dumps({"compared_words": len(words), "differences": len(differences)}))
