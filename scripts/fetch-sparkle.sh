#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD/.build/Sparkle-2.10.0"
if [[ ! -x "$ROOT/bin/sign_update" ]]; then
    mkdir -p "$ROOT"
    curl --fail --silent --show-error --location https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz --output "$ROOT/archive.tar.xz"
    echo 'c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c  '"$ROOT/archive.tar.xz" | shasum -a 256 -c - >&2
    tar -xJf "$ROOT/archive.tar.xz" -C "$ROOT"
fi
printf '%s\n' "$ROOT"
