#!/bin/zsh

set -euo pipefail

# Build the app and put it in /Applications ready to open.
#
# An ad-hoc signature is a real signature: macOS runs it, and TCC will hold a
# Screen Recording grant against it. What macOS refuses to run is a bundle
# still carrying com.apple.quarantine, which a browser attaches to anything it
# downloads and which nothing here ever acquires — a bundle built on this Mac
# was never downloaded. So installing from source needs no security detour at
# all, and this script is only doing the copy carefully.

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"
built_app="$project_dir/dist/Babelstaarnet.app"
installed_app="/Applications/Babelstaarnet.app"

if [[ "${SKIP_BUILD:-}" != "1" ]]; then
    "$script_dir/build-app.sh"
fi

if [[ ! -d "$built_app" ]]; then
    echo "No app to install at $built_app. Run make app first."
    exit 1
fi

codesign --verify --deep --strict "$built_app"

if [[ ! -w /Applications ]]; then
    echo "/Applications is not writable by this account."
    echo "Install it from an administrator account, or drag the app there."
    exit 1
fi

# The bundle cannot be replaced under a copy of it that is still running, and
# a hover session holds an event tap, so any running copy is asked to go
# first — whichever folder it was started from.
if pgrep -f "/Babelstaarnet.app/Contents/MacOS/Babelstaarnet" >/dev/null 2>&1; then
    echo "Quitting the running copy."
    pkill -f "/Babelstaarnet.app/Contents/MacOS/Babelstaarnet" || true
    for _ in {1..20}; do
        pgrep -f "/Babelstaarnet.app/Contents/MacOS/Babelstaarnet" >/dev/null 2>&1 \
            || break
        sleep 0.25
    done
fi

# Copying over a bundle that is already there leaves whatever the old version
# had and the new one does not, which is how a stale resource outlives the
# release that dropped it. The old bundle goes first.
rm -rf "$installed_app"
/usr/bin/ditto "$built_app" "$installed_app"

# Nothing built here is quarantined, but a bundle that once arrived as a
# download and was copied into the source tree would carry the flag into the
# copy, so it is cleared rather than assumed absent.
xattr -d -r com.apple.quarantine "$installed_app" 2>/dev/null || true

codesign --verify --deep --strict "$installed_app"

echo "Installed $installed_app"
open "$installed_app"
echo "Babelstårnet is running. It has no Dock icon — look for it in the menu bar."
