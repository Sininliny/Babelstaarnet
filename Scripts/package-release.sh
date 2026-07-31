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
dmg_name="Babelstaarnet-${version}-macOS.dmg"
dmg_path="$project_dir/dist/$dmg_name"
staging_root="$(mktemp -d "${TMPDIR:-/tmp}/babelstaarnet-release.XXXXXX")"
payload_dir="$staging_root/Babelstårnet"

cleanup() {
    rm -rf "$staging_root"
}
trap cleanup EXIT

"$script_dir/build-app.sh"
codesign --verify --deep --strict "$app_path"

mkdir -p "$payload_dir"
/usr/bin/ditto "$app_path" "$payload_dir/Babelstaarnet.app"
ln -s /Applications "$payload_dir/Applications"
cp "$project_dir/Resources/Start Here.txt" "$payload_dir/Start Here.txt"

hdiutil create \
    -volname "Babelstårnet" \
    -srcfolder "$payload_dir" \
    -format UDZO \
    -ov \
    "$dmg_path"
hdiutil verify "$dmg_path"

(
    cd "$project_dir/dist"
    /usr/bin/shasum -a 256 "$dmg_name" > "$dmg_name.sha256"
)

echo "Packaged $dmg_path"
echo "Checksum $dmg_path.sha256"
