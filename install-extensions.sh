#!/bin/bash
# Install the BFL menu extension and the BFL image generation command.
# Safe to re-run; replaces existing extension and command files.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXT_SRC="$SCRIPT_DIR/extensions/omarchy-menu.jsonc"
BIN_SRC="$SCRIPT_DIR/bin"

EXT_DEST="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
BIN_DEST="$HOME/.local/bin"

if [[ ! -f $EXT_SRC ]]; then
  echo "Error: extension source not found at $EXT_SRC" >&2
  exit 1
fi

if [[ ! -d $BIN_SRC ]]; then
  echo "Error: command source not found at $BIN_SRC" >&2
  exit 1
fi

mkdir -p "$(dirname "$EXT_DEST")"
cp -a "$EXT_SRC" "$EXT_DEST"
echo "Extension installed: $EXT_DEST"

mkdir -p "$BIN_DEST"
if [[ -f $BIN_SRC/omarchy-bfl-generate ]]; then
  cp -a "$BIN_SRC/omarchy-bfl-generate" "$BIN_DEST/omarchy-bfl-generate"
  chmod +x "$BIN_DEST/omarchy-bfl-generate"
  echo "Command installed: $BIN_DEST/omarchy-bfl-generate"
fi

if ! command -v omarchy-bfl-generate >/dev/null 2>&1; then
  echo "Warning: $BIN_DEST is not on PATH. Add it to PATH or restart your shell." >&2
fi

# Refresh the Omarchy menu so the new entries appear immediately.
omarchy menu refresh >/dev/null 2>&1 || true

echo "BFL entries will appear under Trigger → BFL in the Omarchy menu."
