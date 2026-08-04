#!/bin/zsh

set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="$project_dir/.build/runtime-checks"
fixture="$output_dir/danish-screen.png"
bridge="$project_dir/Resources/LocalEngines/argos_bridge.py"
support_dir="${HOME}/Library/Application Support/Babelstaarnet"
python_path="$support_dir/argos-venv/bin/python3"
argos_root="$support_dir/Argos"

mkdir -p "$output_dir"

if [[ ! -x /opt/homebrew/bin/tesseract ]]; then
    echo "Tesseract is not installed. Run make install-engines."
    exit 1
fi

if [[ ! -x "$python_path" ]]; then
    echo "Argos is not installed. Run make install-engines."
    exit 1
fi

swiftc \
    -parse-as-library \
    -module-cache-path "$output_dir/module-cache" \
    "$project_dir/Tests/RuntimeChecks/FixtureGenerator.swift" \
    -o "$output_dir/FixtureGenerator"
"$output_dir/FixtureGenerator" "$fixture"

swiftc \
    -parse-as-library \
    -module-cache-path "$output_dir/module-cache" \
    "$project_dir/Sources/Babelstaarnet/Models/TextModels.swift" \
    "$project_dir/Sources/Babelstaarnet/Services/BoundedCache.swift" \
    "$project_dir/Sources/Babelstaarnet/Services/OCRRoutingPolicy.swift" \
    "$project_dir/Sources/Babelstaarnet/Services/TesseractOCRService.swift" \
    "$project_dir/Sources/Babelstaarnet/Services/OCRService.swift" \
    "$project_dir/Tests/RuntimeChecks/OCRServiceCheck.swift" \
    -o "$output_dir/OCRServiceCheck"
"$output_dir/OCRServiceCheck" "$fixture"

swiftc \
    -parse-as-library \
    -module-cache-path "$output_dir/module-cache" \
    "$project_dir/Sources/Babelstaarnet/Services/ArgosTranslationService.swift" \
    "$project_dir/Tests/RuntimeChecks/ArgosServiceCheck.swift" \
    -o "$output_dir/ArgosServiceCheck"
"$output_dir/ArgosServiceCheck"

ocr_output="$(
    /opt/homebrew/bin/tesseract \
        "$fixture" \
        stdout \
        -l dan \
        --oem 1 \
        --psm 6 \
        2>/dev/null
)"

if [[ "$ocr_output" != *"Godmorgen"* ]] \
    || [[ "$ocr_output" != *"Jeg lærer dansk"* ]]; then
    echo "Tesseract did not recognize the Danish fixture:"
    echo "$ocr_output"
    exit 1
fi

translation_output="$(
    printf '%s' \
        '{"texts":["Godmorgen, hvordan har du det?","Jeg lærer dansk hver dag.","ordbog"]}' \
        | env \
            XDG_DATA_HOME="$argos_root/data" \
            XDG_CONFIG_HOME="$argos_root/config" \
            XDG_CACHE_HOME="$argos_root/cache" \
            ARGOS_CHUNK_TYPE=MINISBD \
            ARGOS_DEVICE_TYPE=cpu \
            "$python_path" \
            "$bridge" \
            --batch \
            --source da \
            --target en
)"

if [[ "$translation_output" != *"Good morning"* ]] \
    || [[ "$translation_output" != *"dictionary"* ]]; then
    echo "Argos did not translate the Danish fixture:"
    echo "$translation_output"
    exit 1
fi

echo "Runtime checks passed"
echo "OCR: $ocr_output"
echo "Translation: $translation_output"
