#!/bin/zsh

# Measures OCR accuracy across colour and format variations.
#
#   ./Scripts/benchmark-ocr.sh                  compare against the recorded
#                                               baseline
#   ./Scripts/benchmark-ocr.sh --record         overwrite the baseline
#
# The baseline lives in .build so it never enters a commit by accident.

set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="$project_dir/.build/ocr-benchmark"
baseline="$output_dir/baseline.json"

mkdir -p "$output_dir"

cd "$project_dir"
swift build -c release -Xswiftc -enable-testing --target BabelstaarnetKit
module="$(swift build -c release --show-bin-path)/BabelstaarnetKit.o"

swiftc \
    -O \
    -parse-as-library \
    -module-cache-path "$output_dir/module-cache" \
    -I "$(dirname "$module")" \
    "$module" \
    "$project_dir/Tests/RuntimeChecks/OCRColorFormatFixtures.swift" \
    "$project_dir/Tests/RuntimeChecks/OCRColorFormatBenchmark.swift" \
    -o "$output_dir/OCRColorFormatBenchmark"

if [[ "${1:-}" == "--record" ]]; then
    "$output_dir/OCRColorFormatBenchmark" --record "$baseline"
    exit 0
fi

if [[ -f "$baseline" ]]; then
    "$output_dir/OCRColorFormatBenchmark" --baseline "$baseline" "${@}"
else
    "$output_dir/OCRColorFormatBenchmark" "${@}"
fi
