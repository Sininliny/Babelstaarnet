#!/bin/zsh

set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${CONFIGURATION:-release}"
app_dir="$project_dir/dist/Babelstaarnet.app"
binary_dir="$app_dir/Contents/MacOS"
resource_dir="$app_dir/Contents/Resources"
module_cache="$project_dir/.build/module-cache"

cd "$project_dir"
mkdir -p "$module_cache"
env \
    CLANG_MODULE_CACHE_PATH="$module_cache" \
    SWIFTPM_MODULECACHE_OVERRIDE="$module_cache" \
    swift build \
    --disable-sandbox \
    -debug-info-format none \
    -c "$configuration" \
    --product Babelstaarnet

binary_path="$(
    env \
        CLANG_MODULE_CACHE_PATH="$module_cache" \
        SWIFTPM_MODULECACHE_OVERRIDE="$module_cache" \
        swift build \
        --disable-sandbox \
        -c "$configuration" \
        --show-bin-path
)/Babelstaarnet"

mkdir -p "$binary_dir" "$resource_dir"
cp "$binary_path" "$binary_dir/Babelstaarnet"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
mkdir -p "$resource_dir/LocalEngines"
cp "$project_dir/Resources/LocalEngines/argos_bridge.py" \
    "$resource_dir/LocalEngines/argos_bridge.py"
cp "$project_dir/Scripts/install-local-engines.sh" \
    "$resource_dir/LocalEngines/install-local-engines.sh"

signing_identity="${SIGNING_IDENTITY:-}"

if [[ -n "$signing_identity" ]]; then
    codesign \
        --force \
        --deep \
        --options runtime \
        --timestamp=none \
        --sign "$signing_identity" \
        "$app_dir"
    echo "Signed with $signing_identity"
else
    codesign \
        --force \
        --deep \
        --sign - \
        --requirements '=designated => identifier "dev.sinin.babelstaarnet"' \
        "$app_dir"
    echo "Ad-hoc signed with a stable designated requirement for local TCC access."
fi

echo "Built $app_dir"
