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

# The two build systems in circulation lay their products out differently. One
# leaves a whole-module object per target beside the archives; the other leaves
# only the archives, and globbing for objects then found nothing on a clean
# checkout while passing on any machine with a stale `.build` full of them.
#
# So: take the object for every module that has one, and the archive for every
# module that does not, which links each module exactly once whichever system
# built it. The archives are handed over as plain inputs and not force-loaded —
# one of these systems writes an archive holding the module's dependencies as
# well as the module, so forcing them all in defines several modules twice.
link_inputs=()
for object in "$bin_dir"/*.o(N); do
    link_inputs+=("$object")
done
for archive in "$bin_dir"/*.a(N); do
    module="${${archive:t:r}#lib}"
    if [[ ! -e "$bin_dir/$module.o" ]]; then
        link_inputs+=("$archive")
    fi
done

if (( ${#link_inputs} == 0 )); then
    echo "No built modules found in $bin_dir"
    exit 1
fi

for check in "$check_dir"/*.swift; do
    name="${check:t:r}"
    swiftc \
        -parse-as-library \
        -module-cache-path "$output_dir/module-cache" \
        -I "$bin_dir" \
        "${link_inputs[@]}" \
        "$check" \
        -o "$output_dir/$name"
    "$output_dir/$name"
done
