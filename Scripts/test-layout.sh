#!/bin/zsh

set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="$project_dir/.build/layout-checks"
check_dir="$project_dir/Tests/BabelstaarnetTests"

mkdir -p "$output_dir"
cd "$project_dir"

# Each check is its own small binary that fails loudly on a precondition, and
# links every module rather than a hand-listed set of source files. The list
# used to be maintained per check, which meant every file that moved between
# modules broke a script nobody was editing at the time.
swift build
bin_dir="$(swift build --show-bin-path)"
module_objects=("$bin_dir"/*.o(N))

if (( ${#module_objects} == 0 )); then
    echo "No built modules found in $bin_dir"
    exit 1
fi

for check in "$check_dir"/*.swift; do
    name="${check:t:r}"
    swiftc \
        -parse-as-library \
        -module-cache-path "$output_dir/module-cache" \
        -I "$bin_dir" \
        "${module_objects[@]}" \
        "$check" \
        -o "$output_dir/$name"
    "$output_dir/$name"
done
