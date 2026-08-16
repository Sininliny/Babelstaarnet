#!/bin/zsh

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"
info_plist="$project_dir/Resources/Info.plist"
version="$(
    /usr/libexec/PlistBuddy \
        -c "Print :CFBundleShortVersionString" \
        "$info_plist"
)"
app_path="$project_dir/dist/Babelstaarnet.app"
stage_root="$project_dir/dist/stage"
stage_dir="$stage_root/Babelstaarnet $version"
zip_name="Babelstaarnet-${version}-macOS.zip"
zip_path="$project_dir/dist/$zip_name"

# The notarizing job in CI staples its ticket to the app after this script has
# already run, and then needs the archive built again around the stapled
# bundle. It re-runs this with SKIP_BUILD=1 rather than rebuilding, so that
# the archive it publishes is made the same way as the one it replaces.
if [[ "${SKIP_BUILD:-}" != "1" ]]; then
    "$script_dir/build-app.sh"
fi

codesign --verify --deep --strict "$app_path"

# A ZIP, and only a ZIP.
#
# The DMG this used to build alongside it was the drag-to-Applications
# package, which is the right shape for an app that opens with a double
# click. Without a paid Apple Developer ID this one does not: it can be
# ad-hoc signed but not notarized, so on arrival macOS holds it for the
# quarantine flag the browser attached to the download. A disk image cannot
# make that go away — it only adds a second download of the same bytes, a
# second checksum, and a mount step before the same warning. Restore it on
# the day the app is notarized.
#
# What does help is that the thing standing between the reader and the app is
# a flag on a file rather than anything wrong with the app, so the archive
# carries a plain-text installer that clears it, next to the instructions for
# doing it by hand in System Settings instead.
rm -rf "$stage_root"
mkdir -p "$stage_dir"
/usr/bin/ditto "$app_path" "$stage_dir/Babelstaarnet.app"
/usr/bin/ditto \
    "$project_dir/Resources/Install Babelstaarnet.command" \
    "$stage_dir/Install Babelstaarnet.command"
/usr/bin/ditto \
    "$project_dir/Resources/Start Here.txt" \
    "$stage_dir/Start Here.txt"
chmod +x "$stage_dir/Install Babelstaarnet.command"

rm -f "$zip_path"
/usr/bin/ditto \
    -c \
    -k \
    --sequesterRsrc \
    --keepParent \
    "$stage_dir" \
    "$zip_path"

rm -rf "$stage_root"

(
    cd "$project_dir/dist"
    /usr/bin/shasum -a 256 "$zip_name" > "$zip_name.sha256"
)

echo "Packaged $zip_path"
echo "Checksum $zip_path.sha256"
