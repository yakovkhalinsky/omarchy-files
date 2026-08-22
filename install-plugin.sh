#!/bin/bash
# Install the odessa.agents Omarchy bar plugin and the Pi usage collector.
# Safe to re-run; replaces the existing plugin and collector files.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SRC="$SCRIPT_DIR/plugin/odessa.agents"
BIN_SRC="$SCRIPT_DIR/bin"

PLUGIN_DEST="$HOME/.config/omarchy/plugins/odessa.agents"
BIN_DEST="$HOME/.local/bin"

if [[ ! -d $PLUGIN_SRC ]]; then
  echo "Error: plugin source not found at $PLUGIN_SRC" >&2
  exit 1
fi

if [[ ! -d $BIN_SRC ]]; then
  echo "Error: collector source not found at $BIN_SRC" >&2
  exit 1
fi

mkdir -p "$PLUGIN_DEST"
rm -rf "$PLUGIN_DEST"/*
cp -a "$PLUGIN_SRC"/. "$PLUGIN_DEST/"
echo "Plugin installed to $PLUGIN_DEST"

if ! omarchy plugin validate "$PLUGIN_DEST"; then
  echo "Warning: plugin validation failed" >&2
fi

mkdir -p "$BIN_DEST"
for file in omarchy-agent-usage-pi omarchy-agent-usage-update; do
  if [[ -f $BIN_SRC/$file ]]; then
    cp -a "$BIN_SRC/$file" "$BIN_DEST/$file"
    chmod +x "$BIN_DEST/$file"
    echo "Collector installed: $BIN_DEST/$file"
  fi
done

# The packaged updater lives in /usr/share/omarchy/bin. To make the wrapper
# shadow it, this repo also installs the wrapper where the Pi tool places its
# own bin directory (usually earlier on PATH than /usr/share/omarchy/bin).
PI_AGENT_BIN="$HOME/.pi/agent/bin"
if [[ -d $PI_AGENT_BIN ]]; then
  cp -a "$BIN_SRC/omarchy-agent-usage-update" "$PI_AGENT_BIN/omarchy-agent-usage-update"
  chmod +x "$PI_AGENT_BIN/omarchy-agent-usage-update"
  echo "Wrapper shadowing packaged updater: $PI_AGENT_BIN/omarchy-agent-usage-update"
fi

if ! command -v omarchy-agent-usage-pi >/dev/null 2>&1; then
  echo "Warning: $BIN_DEST is not on PATH. Add it to PATH or restart your shell." >&2
fi

# Warn if the packaged updater is still first on PATH (the wrapper won't be used).
update_path=$(command -v omarchy-agent-usage-update || true)
if [[ -n $update_path && $update_path == /usr/share/omarchy/bin/* ]]; then
  echo "Warning: $update_path is first on PATH. The Pi auto-refresh wrapper will not be used." >&2
  echo "  Install pi with mise, or put $BIN_DEST before /usr/share/omarchy/bin on PATH." >&2
fi

omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
echo "Run: omarchy plugin enable odessa.agents --section right"
