"""Keep the Windows language data identical to LanguageDanish/Danish.swift."""
import argparse, json, re
from pathlib import Path
root = Path(__file__).resolve().parents[1]
source = (root / "Sources/LanguageDanish/Danish.swift").read_text(encoding="utf-8")
def table(name):
    body = re.search(r"private static let " + name + r"[^=]*= \[(.*?)\n    \]", source, re.S).group(1)
    return dict(re.findall(r'"([^"]+)": "([^"]*)"', body))
def strings(field):
    body = re.search(field + r": \[(.*?)\]", source, re.S).group(1)
    return re.findall(r'"([^"]+)"', re.sub(r"//[^\n]*", "", body))
def prompt(field):
    text = re.search(field + r': """\n(.*?)\n            """', source, re.S).group(1)
    return "\n".join(line[12:] for line in text.splitlines())
data = dict(source="Sources/LanguageDanish/Danish.swift", code="da",
    abbreviations=strings("abbreviations"), structuralWords=strings("structuralWords"), meaningPreservationWords=strings("meaningPreservationWords"),
    glosses=table("danishClosedClassGlosses"), beginner=table("danishBeginnerGlosses"),
    newsSimplificationInstructions=prompt("newsSimplificationInstructions"),
    glossInstructions=prompt("glossInstructions"), explainInstructions=prompt("explainInstructions"))
exact = re.search(r"exactGlosses: \[(.*?)\n        \]", source, re.S).group(1)
data["glosses"].update(dict(re.findall(r'"([^"]+)": "([^"]*)"', exact)))
target = root / "Resources/LanguagePacks/da.json"
expected = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
parser = argparse.ArgumentParser(); parser.add_argument("--check", action="store_true"); args = parser.parse_args()
if args.check:
    if not target.exists() or target.read_text(encoding="utf-8") != expected:
        raise SystemExit("Windows Danish data is stale; run Scripts/sync-windows-language.py.")
else:
    target.parent.mkdir(parents=True, exist_ok=True); target.write_text(expected, encoding="utf-8", newline="\n")
print("Danish language tables and prompts match the Mac source.")
