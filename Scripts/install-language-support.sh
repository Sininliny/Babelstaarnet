#!/bin/zsh
set -euo pipefail
source_language="${1:-da}"
target_language="${2:-en}"
case "$source_language" in da|en|zh-Hans|zh-Hant) ;; *) exit 2 ;; esac
case "$target_language" in da|en|zh-Hans|zh-Hant) ;; *) exit 2 ;; esac
script_dir="$(cd "$(dirname "$0")" && pwd)"
support_dir="${BABELSTAARNET_DATA_DIRECTORY:-$HOME/Library/Application Support/Babelstaarnet}"
if [[ -f "$script_dir/language_support.py" ]]; then helper="$script_dir/language_support.py"
else helper="$script_dir/../Resources/LocalEngines/language_support.py"; fi
managed="$support_dir/argos-venv/bin/python3"
if [[ ! -x "$managed" ]]; then
    python_path=""
    for candidate in /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3; do
        if [[ -x "$candidate" ]]; then python_path="$candidate"; break; fi
    done
    [[ -n "$python_path" ]] || { echo 'Install Python 3.12 first.'; exit 2; }
    "$python_path" -c 'import sys; assert (3,10) <= sys.version_info < (3,14), "Install Python 3.10-3.13"'
    mkdir -p "$support_dir"
    "$python_path" -m venv "$support_dir/argos-venv"
fi
dependencies=('opencc-python-reimplemented==0.1.7')
if [[ "$source_language" != zh-* || "$target_language" != zh-* ]]; then dependencies+=('argostranslate>=1.10,<2'); fi
"$managed" -m pip install "${dependencies[@]}"
"$managed" "$helper" install --data-directory "$support_dir" --source "$source_language" --target "$target_language"
export XDG_DATA_HOME="$support_dir/Argos/data" XDG_CONFIG_HOME="$support_dir/Argos/config" XDG_CACHE_HOME="$support_dir/Argos/cache"
export ARGOS_PACKAGES_DIR="$XDG_DATA_HOME/argos-translate/packages"
"$managed" "${helper:h}/argos_bridge.py" --check-word-model --source "$source_language" --target "$target_language"
