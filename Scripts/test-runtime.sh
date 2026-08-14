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

# Built optimized because this check asserts latency budgets, and the app
# itself ships as a release build. An unoptimized binary would measure a
# configuration no user runs. `-enable-testing` is what lets the check reach
# the library's internals; it also keeps a little more of the module alive
# through optimization, so timings recorded before this became a module build
# are not comparable with timings recorded after it.
swift build -c release -Xswiftc -enable-testing --target BabelstaarnetKit
release_module="$(swift build -c release --show-bin-path)/BabelstaarnetKit.o"

swiftc \
    -O \
    -parse-as-library \
    -module-cache-path "$output_dir/module-cache" \
    -I "$(dirname "$release_module")" \
    "$release_module" \
    "$project_dir/Tests/RuntimeChecks/OCRServiceCheck.swift" \
    -o "$output_dir/OCRServiceCheck"
"$output_dir/OCRServiceCheck" "$fixture"

# The debug module, because the bridge script has to still be found beside the
# checkout: a build with no bundle to read it from locates it relative to the
# working directory, and that development-only path is gated on DEBUG — which
# a debug build of the library is what defines.
swift build --target BabelstaarnetKit
debug_module="$(swift build --show-bin-path)/BabelstaarnetKit.o"

swiftc \
    -parse-as-library \
    -module-cache-path "$output_dir/module-cache" \
    -I "$(dirname "$debug_module")" \
    "$debug_module" \
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
