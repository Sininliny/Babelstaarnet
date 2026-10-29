"""Fast, platform-independent repository contracts. No model or network needed."""
import json
import plistlib
import subprocess
import sys
from pathlib import Path
from xml.etree import ElementTree

root = Path(__file__).resolve().parents[1]
with (root / "Resources/Info.plist").open("rb") as stream:
    version = plistlib.load(stream)["CFBundleShortVersionString"]
app = ElementTree.parse(root / "Windows/Babelstaarnet.Windows/Babelstaarnet.Windows.csproj")
assert app.findtext("PropertyGroup/Version") == version, "Windows and Mac app versions must agree"
solution = ElementTree.parse(root / "Babelstaarnet.slnx")
for project in solution.findall(".//Project"):
    path = root / project.attrib["Path"]
    assert path.is_file(), f"Missing solution project: {path}"
    for reference in ElementTree.parse(path).findall(".//ProjectReference"):
        assert (path.parent / reference.attrib["Include"]).is_file(), "Broken project reference"
core = ElementTree.parse(root / "Windows/Babelstaarnet.Core/Babelstaarnet.Core.csproj")
assert not core.findall(".//ProjectReference"), "Core must not depend on a platform application"
assert not core.findall(".//UseWPF"), "Core must stay independent of Windows UI"
assert not core.findall(".//UseWindowsForms"), "Core must stay independent of Windows Forms"
assert "windows" not in core.findtext("PropertyGroup/TargetFramework", "").lower(), "Core must target portable .NET"
fixtures = json.loads((root / "Tests/Shared/reading-contract.json").read_text(encoding="utf-8"))
assert fixtures["schemaVersion"] == 1 and fixtures["language"] == "da"
assert fixtures["identities"] and fixtures["sentences"]
subprocess.run([sys.executable, str(root / "Scripts/sync-windows-language.py"), "--check"], check=True)
subprocess.run([sys.executable, str(root / "Tests/Shared/gloss-protocol-check.py")], check=True)
subprocess.run([sys.executable, str(root / "Tests/Shared/language-support-check.py")], check=True)
print(f"Repository references, platform boundaries, version {version} and shared fixtures passed.")
