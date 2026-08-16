#!/bin/zsh

# BABELSTÅRNET INSTALLER
#
# This file is plain text on purpose. Read it before you run it.
#
# Babelstårnet is signed, but with an ad-hoc signature rather than an Apple
# Developer ID, because the project is not enrolled in the Apple Developer
# Program. macOS runs ad-hoc signed apps perfectly well. What it refuses to
# open is anything still carrying the com.apple.quarantine flag your browser
# attached to this download, and for an app that is not notarized there is no
# "open anyway" inside that refusal — only the one in System Settings.
#
# So this installer does exactly three things, and you can do all three by
# hand instead if you would rather:
#
#   1. copies Babelstaarnet.app into /Applications
#   2. removes the quarantine flag from the copy it just made
#   3. opens it
#
# It touches nothing else, asks for no password, and installs nothing else.

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
source_app="$here/Babelstaarnet.app"
installed_app="/Applications/Babelstaarnet.app"

echo
echo "Babelstårnet — install"
echo "----------------------"
echo

if [[ ! -d "$source_app" ]]; then
    echo "Babelstaarnet.app is not in this folder."
    echo
    echo "Keep this file next to the app: extract the whole downloaded ZIP,"
    echo "then run this from inside the folder it made."
    echo
    exit 1
fi

# A quarantined app cannot be trusted to be the app that was signed, so the
# signature is checked before the flag is dropped rather than after. If this
# fails the download is damaged or altered, and the right move is to fetch it
# again rather than to install it.
echo "Checking the app's signature…"
if ! codesign --verify --deep --strict "$source_app" 2>/dev/null; then
    echo
    echo "This copy of Babelstaarnet.app does not match its own signature."
    echo "Download it again from the Releases page; do not install this one."
    echo
    exit 1
fi
echo "Signature is intact."

if [[ ! -w /Applications ]]; then
    echo
    echo "/Applications is not writable by this account. Use an administrator"
    echo "account, or install to your own folder instead:"
    echo "    ~/Applications"
    echo
    exit 1
fi

# The bundle cannot be replaced under a copy of it that is still running.
if pgrep -f "/Babelstaarnet.app/Contents/MacOS/Babelstaarnet" >/dev/null 2>&1; then
    echo "Quitting the copy that is already running…"
    pkill -f "/Babelstaarnet.app/Contents/MacOS/Babelstaarnet" || true
    for _ in {1..20}; do
        pgrep -f "/Babelstaarnet.app/Contents/MacOS/Babelstaarnet" >/dev/null 2>&1 \
            || break
        sleep 0.25
    done
fi

echo "Copying to /Applications…"
rm -rf "$installed_app"
/usr/bin/ditto "$source_app" "$installed_app"

echo "Removing the download flag…"
xattr -d -r com.apple.quarantine "$installed_app" 2>/dev/null || true

# The copy is verified again, because a signature that was intact in the
# download and is not intact in /Applications means the copy went wrong.
codesign --verify --deep --strict "$installed_app"

echo "Opening Babelstårnet…"
open "$installed_app"

echo
echo "Installed."
echo
echo "Babelstårnet has no Dock icon. Look for it in the menu bar."
echo
echo "Next: click \"Set up Babelstårnet\", enable it under Screen Recording"
echo "in the System Settings page that opens, and relaunch if macOS asks."
echo "Then press fn + Z and hover a Danish word."
echo
echo "You can close this window."
echo
