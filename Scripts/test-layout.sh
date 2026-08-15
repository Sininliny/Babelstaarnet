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

# Finding what to link against is the fiddly part, because the toolchains
# disagree three ways and the script only ever saw one of them. Locally it
# globbed the path `swift build --show-bin-path` reports and found a
# whole-module object per target; on a clean checkout that path can be empty,
# because the newer build system reports one directory and writes to another.
# Nothing here can be assumed: not where the products are, not whether they
# are objects or archives, and not whether the compiled modules sit beside
# them. So each is searched for, by name, under `.build`.
#
# The old glob passed on any machine with a stale `.build` full of objects and
# failed on every machine that had only just built the package — which is what
# CI is, every time.
module_dirs=()
for module in "$project_dir"/.build/**/BabelstaarnetKit.swiftmodule(N:h); do
    module_dirs+=("$module")
done

product_dirs=()
for product in \
    "$project_dir"/.build/**/libBabelstaarnetKit.a(N:h) \
    "$project_dir"/.build/**/BabelstaarnetKit.o(N:h); do
    product_dirs+=("$product")
done

if (( ${#module_dirs} == 0 || ${#product_dirs} == 0 )); then
    echo "No built modules found under $project_dir/.build"
    echo "Reported bin path: $(swift build --show-bin-path)"
    echo "Compiled modules:  ${module_dirs[*]:-none}"
    echo "Linkable products: ${product_dirs[*]:-none}"
    exit 1
fi

# Objects where a module has one, archives where it does not, so each module
# is linked exactly once whichever system built it. Archives are plain inputs
# rather than force-loaded: one of these systems writes an archive holding a
# module's dependencies as well as the module itself, and forcing all of them
# in defines several modules twice.
bin_dir="${product_dirs[1]}"
link_inputs=("$bin_dir"/*.o(N))
for archive in "$bin_dir"/*.a(N); do
    module="${${archive:t:r}#lib}"
    [[ -e "$bin_dir/$module.o" ]] || link_inputs+=("$archive")
done

include_flags=()
for module_dir in "${module_dirs[@]}"; do
    include_flags+=(-I "$module_dir")
done

echo "Linking checks against $bin_dir"

for check in "$check_dir"/*.swift; do
    name="${check:t:r}"
    swiftc \
        -parse-as-library \
        -module-cache-path "$output_dir/module-cache" \
        "${include_flags[@]}" \
        "${link_inputs[@]}" \
        "$check" \
        -o "$output_dir/$name"
    "$output_dir/$name"
done
