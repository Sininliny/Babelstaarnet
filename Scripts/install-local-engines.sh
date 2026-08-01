#!/bin/zsh

set -euo pipefail

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

"$brew_path" list tesseract >/dev/null 2>&1 \
    || "$brew_path" install tesseract
"$brew_path" list tesseract-lang >/dev/null 2>&1 \
    || "$brew_path" install tesseract-lang
"$brew_path" list python@3.12 >/dev/null 2>&1 \
    || "$brew_path" install python@3.12

python_path="$("$brew_path" --prefix python@3.12)/bin/python3.12"

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
"$virtual_environment/bin/python3" -m pip install --upgrade \
    pip \
    argostranslate \
    nltk
wordnet_directory="$word_bridge_data_root/corpora/wordnet"
if [[ ! -f "$wordnet_directory/index.noun" ]]; then
    mkdir -p "$word_bridge_data_root/corpora"
    wordnet_archive="$word_bridge_data_root/wordnet.zip"
    /usr/bin/curl \
        --fail \
        --location \
        --silent \
        --show-error \
        "https://raw.githubusercontent.com/nltk/nltk_data/gh-pages/packages/corpora/wordnet.zip" \
        --output "$wordnet_archive"
    /usr/bin/ditto \
        -x \
        -k \
        "$wordnet_archive" \
        "$word_bridge_data_root/corpora"
fi
"$virtual_environment/bin/python3" "$bridge" \
    --install \
    --source da \
    --target en
"$virtual_environment/bin/python3" "$bridge" \
    --install \
    --source en \
    --target da

echo "OCR, translation, and the adaptive word bridge are ready."
