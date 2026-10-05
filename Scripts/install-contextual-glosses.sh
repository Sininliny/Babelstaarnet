#!/bin/zsh

# Adds contextual glosses to an existing local-engine installation: the
# mlx-lm package in the private Python environment, and a 4-bit Gemma 3 4B
# model in Application Support.
#
# Everything this downloads is pinned. The package is installed at an exact
# version, and the model is fetched from one fixed revision and each file
# checked against a SHA-256 recorded here before anything is moved to where
# the app loads it from. A download that does not match leaves the previous
# state untouched.

set -euo pipefail

support_dir="${HOME}/Library/Application Support/Babelstaarnet"
virtual_environment="$support_dir/argos-venv"
models_dir="$support_dir/Models"
model_name="gemma-3-text-4b-it-4bit"
model_dir="$models_dir/$model_name"
repository="mlx-community/gemma-3-text-4b-it-4bit"
revision="4f665a4c50ecfe4ecdc34056ab52fe3e3c4abf9e"
mlx_lm_version="0.31.3"

# name, SHA-256
model_files=(
    added_tokens.json 50b2f405ba56a26d4913fd772089992252d7f942123cc0a034d96424221ba946
    config.json 1ec76c3aa6640ad351da97962d9d02672490ad5363aad5b791517d0e605e0058
    model.safetensors 4992b5af91dcece8eb3911dd02c4196a7bb88c5379918f19a0b1e1be93f64ac6
    model.safetensors.index.json d4d8fb0c387778633df070716187884efce2ace932802e88005d11ad5d3f554a
    special_tokens_map.json 2f7b0adf4fb469770bb1490e3e35df87b1dc578246c5e7e6fc76ecf33213a397
    tokenizer.json 4667f2089529e8e7657cfb6d1c19910ae71ff5f28aa7ab2ff2763330affad795
    tokenizer.model 1299c11d7cf632ef3b4e11937501358ada021bbdf7c47638d13c0ee982f2e79c
    tokenizer_config.json bfe25c2735e395407beb78456ea9a6984a1f00d8c16fa04a8b75f2a614cf53e1
)

if [[ "$(/usr/bin/uname -m)" != "arm64" ]]; then
    echo "Contextual glosses need Apple silicon: the model runs on MLX."
    exit 1
fi

if [[ ! -x "$virtual_environment/bin/python3" ]]; then
    echo "The local engines are not installed yet."
    echo "Install them first (Settings → Local engines, or make install-engines)."
    exit 1
fi

"$virtual_environment/bin/python3" -m pip install --quiet \
    "mlx-lm==$mlx_lm_version"

mkdir -p "$models_dir"
staging="$(/usr/bin/mktemp -d "$models_dir/.$model_name.XXXXXX")"
trap '/bin/rm -rf "$staging"' EXIT

for name expected in "${model_files[@]}"; do
    target="$model_dir/$name"
    # A file already in place and already matching is not fetched again, so
    # an interrupted or repeated install does not re-download 2.6 GB.
    if [[ -f "$target" ]] \
        && [[ "$(/usr/bin/shasum -a 256 "$target" | cut -d' ' -f1)" == "$expected" ]]; then
        /bin/cp -c "$target" "$staging/$name"
        continue
    fi
    echo "Downloading $name"
    /usr/bin/curl \
        --fail \
        --location \
        --silent \
        --show-error \
        --retry 3 \
        "https://huggingface.co/$repository/resolve/$revision/$name" \
        --output "$staging/$name"
    actual="$(/usr/bin/shasum -a 256 "$staging/$name" | cut -d' ' -f1)"
    if [[ "$actual" != "$expected" ]]; then
        echo "$name did not match its pinned hash; nothing was installed."
        echo "expected $expected"
        echo "received $actual"
        exit 1
    fi
done

# Swapped in whole, so the app never sees a directory half old and half new.
/bin/rm -rf "$model_dir.previous"
if [[ -d "$model_dir" ]]; then
    /bin/mv "$model_dir" "$model_dir.previous"
fi
/bin/mv "$staging" "$model_dir"
trap - EXIT
/bin/rm -rf "$model_dir.previous"

echo "Contextual glosses are ready."
