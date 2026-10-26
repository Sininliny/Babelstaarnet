#!/bin/zsh

set -euo pipefail

progress() {
    printf 'BABELSTAARNET_PROGRESS\t%s\t9\t%s\n' "$1" "$2"
}
progress 0 "Checking installation requirements"

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"
support_dir="${HOME}/Library/Application Support/Babelstaarnet"
virtual_environment="$support_dir/argos-venv"
argos_data_root="$support_dir/Argos"
word_bridge_data_root="$support_dir/WordWise"
if [[ -f "$script_dir/argos_bridge.py" ]]; then
    bridge="$script_dir/argos_bridge.py"
else
    bridge="$project_dir/Resources/LocalEngines/argos_bridge.py"
fi

if [[ -x /opt/homebrew/bin/brew ]]; then
    brew_path=/opt/homebrew/bin/brew
elif [[ -x /usr/local/bin/brew ]]; then
    brew_path=/usr/local/bin/brew
elif command -v brew >/dev/null 2>&1; then
    brew_path="$(command -v brew)"
else
    echo "Homebrew is required to install Tesseract."
    echo "Install it from https://brew.sh and run this command again."
    exit 1
fi

progress 1 "Installing Danish OCR"
"$brew_path" list tesseract >/dev/null 2>&1 \
    || "$brew_path" install tesseract
"$brew_path" list tesseract-lang >/dev/null 2>&1 \
    || "$brew_path" install tesseract-lang
progress 2 "Preparing Python"
"$brew_path" list python@3.12 >/dev/null 2>&1 \
    || "$brew_path" install python@3.12

python_path="$("$brew_path" --prefix python@3.12)/bin/python3.12"

# The managed environment and downloaded data belong only to this user.
umask 077
mkdir -p "$support_dir"
mkdir -p \
    "$argos_data_root/data" \
    "$argos_data_root/config" \
    "$argos_data_root/cache" \
    "$word_bridge_data_root"

export XDG_DATA_HOME="$argos_data_root/data"
export XDG_CONFIG_HOME="$argos_data_root/config"
export XDG_CACHE_HOME="$argos_data_root/cache"
export ARGOS_CHUNK_TYPE=MINISBD
export ARGOS_DEVICE_TYPE=cpu
export NLTK_DATA="$word_bridge_data_root"
"$python_path" -m venv "$virtual_environment"
progress 3 "Installing translation libraries"
"$virtual_environment/bin/python3" -m pip install --upgrade \
    --timeout 30 --retries 2 --progress-bar off \
    pip \
    argostranslate \
    nltk
progress 4 "Preparing the word dictionary"
wordnet_directory="$word_bridge_data_root/corpora/wordnet"
# NLTK rejects data writable by another account. Ditto preserved the ZIP's
# group-writable directory mode. Re-download rejected data into a private
# staging directory; do not trust a previously writable dictionary.
if ! "$virtual_environment/bin/python3" -c \
    'from nltk.corpus import wordnet; wordnet.ensure_loaded()' >/dev/null 2>&1; then
    mkdir -p "$word_bridge_data_root/corpora"
    wordnet_staging="$(/usr/bin/mktemp -d "$word_bridge_data_root/.wordnet.XXXXXX")"
    trap '/bin/rm -rf "$wordnet_staging"' EXIT
    wordnet_archive="$wordnet_staging/wordnet.zip"
    /usr/bin/curl \
        --fail \
        --location \
        --silent \
        --show-error \
        --connect-timeout 15 --max-time 300 --retry 2 \
        "https://raw.githubusercontent.com/nltk/nltk_data/gh-pages/packages/corpora/wordnet.zip" \
        --output "$wordnet_archive"
    "$virtual_environment/bin/python3" -m zipfile -e \
        "$wordnet_archive" "$wordnet_staging/extracted/corpora"
    /bin/chmod -R u+rwX,go-rwx "$wordnet_staging/extracted/corpora/wordnet"
    NLTK_DATA="$wordnet_staging/extracted" "$virtual_environment/bin/python3" \
        -c 'from nltk.corpus import wordnet; wordnet.ensure_loaded()'
    if [[ -e "$wordnet_directory.previous" ]]; then
        /bin/rm -rf "$wordnet_directory.previous"
    fi
    if [[ -d "$wordnet_directory" ]]; then
        /bin/mv "$wordnet_directory" "$wordnet_directory.previous"
    fi
    if ! /bin/mv "$wordnet_staging/extracted/corpora/wordnet" "$wordnet_directory"; then
        [[ ! -d "$wordnet_directory.previous" ]] \
            || /bin/mv "$wordnet_directory.previous" "$wordnet_directory"
        exit 1
    fi
    /bin/rm -rf "$wordnet_directory.previous"
    /bin/rm -rf "$wordnet_staging"
    trap - EXIT
fi
progress 5 "Installing Danish to English translation"
"$virtual_environment/bin/python3" "$bridge" \
    --install \
    --source da \
    --target en
progress 6 "Installing English to Danish translation"
"$virtual_environment/bin/python3" "$bridge" \
    --install \
    --source en \
    --target da

progress 7 "Verifying downloaded language resources"
"$virtual_environment/bin/python3" "$bridge" --check
"$virtual_environment/bin/python3" "$bridge" --check-word-bridge --source en --target da
progress 8 "Checking engines in Babelstårnet"
echo "OCR, translation, and the adaptive word bridge are installed."
