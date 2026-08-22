#!/bin/bash
# Install the Netrunner Omarchy theme and its extra backgrounds.
# Safe to re-run; replaces the existing theme files.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME_SRC="$SCRIPT_DIR/theme/netrunner"
BG_SRC="$SCRIPT_DIR/backgrounds/netrunner"

THEME_DEST="$HOME/.config/omarchy/themes/netrunner"
BG_DEST="$HOME/.config/omarchy/backgrounds/netrunner"

if [[ ! -d $THEME_SRC ]]; then
  echo "Error: theme source not found at $THEME_SRC" >&2
  exit 1
fi

mkdir -p "$THEME_DEST"
rm -rf "$THEME_DEST"/*
cp -a "$THEME_SRC"/. "$THEME_DEST/"
echo "Theme installed to $THEME_DEST"

if [[ -d $BG_SRC ]]; then
  mkdir -p "$BG_DEST"
  cp -a "$BG_SRC"/. "$BG_DEST/"
  echo "Extra backgrounds installed to $BG_DEST"
fi

echo "Run: omarchy theme set netrunner"
