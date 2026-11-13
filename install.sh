#!/usr/bin/env bash
set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="${PREFIX}/bin"

mkdir -p "$BIN_DIR"
chmod +x "${REPO_DIR}/bin/tmux-phoenix"

ln -sf "${REPO_DIR}/bin/tmux-phoenix" "${BIN_DIR}/tmux-phoenix"
ln -sf "${REPO_DIR}/bin/tmux-phoenix" "${BIN_DIR}/tpx"

echo "Linked ${BIN_DIR}/tmux-phoenix (and alias 'tpx') -> ${REPO_DIR}/bin/tmux-phoenix"

if [[ ":${PATH}:" != *":${BIN_DIR}:"* ]]; then
    echo "Note: ${BIN_DIR} is not currently in your PATH."
fi

if [ "${SKIP_SETUP:-0}" != "1" ]; then
    "${BIN_DIR}/tmux-phoenix" setup
fi
