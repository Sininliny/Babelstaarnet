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
app_zip_name="Babelstaarnet-${version}-macOS.app.zip"
app_zip_path="$project_dir/dist/$app_zip_name"

"$script_dir/build-app.sh"
codesign --verify --deep --strict "$app_path"

# A ZIP, and only a ZIP.
#
# The DMG this used to build alongside it was the drag-to-Applications
# package, which is the right shape for an app that opens with a double
# click. This one does not: without a paid Apple Developer ID it can only be
# ad-hoc signed, so whichever container it arrives in, the first launch is a
# Control-click and an Open. A disk image cannot make that go away — it only
# adds a second download of the same bytes, a second checksum, and a mount
# step before the same warning. Restore it on the day the app is notarized.
rm -f "$app_zip_path"
/usr/bin/ditto \
    -c \
    -k \
    --sequesterRsrc \
    --keepParent \
    "$app_path" \
    "$app_zip_path"

(
    cd "$project_dir/dist"
    /usr/bin/shasum -a 256 "$app_zip_name" > "$app_zip_name.sha256"
)

echo "Packaged $app_zip_path"
echo "Checksum $app_zip_path.sha256"
