#!/bin/bash
# Install the system-level pieces the omarchy-files repo assumes are present:
#   - google-chrome (AUR) for browsing
#   - ollama (Arch extra, which is the ollama.com binary repackaged) for local models
#   - Hyprland display scaling set to 1.25 (writes via omarchy-hyprland-monitor-scaling
#     so the displays widget stays in sync and the value survives reboots)
#   - pi via mise, with ollama as the default provider and minimax-m3:cloud as the
#     default model
#
# Usage: ./install-system.sh [--apply]
#   --apply  Apply all changes now (default: just install packages and print next steps)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPLY=0

if (( $# > 0 )) && [[ $1 == --apply ]]; then
  APPLY=1
fi

CHROME_PKG="google-chrome"
OLLAMA_PKG="ollama"
OLLAMA_CUDA_PKG="ollama-cuda"
SCALE="1.25"
PI_VERSION="latest"
PI_PROVIDER="ollama"
PI_MODEL="minimax-m3:cloud"

note() { printf '  • %s\n' "$*"; }
ok() { printf '  ✓ %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }
fail() { printf '  ✗ %s\n' "$*" >&2; exit 1; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

# ------------------------------------------------------------------ helpers

# Have we already installed google-chrome (binary or AUR package)?
chrome_installed() {
  command_exists google-chrome-stable || command_exists google-chrome \
    || pacman -Qq "$CHROME_PKG" >/dev/null 2>&1
}

# Have we already installed ollama (binary or package)?
ollama_installed() {
  command_exists ollama || pacman -Qq "$OLLAMA_PKG" >/dev/null 2>&1
}

# Read a JSON value from ~/.pi/agent/settings.json without requiring jq.
# Usage: pi_setting <key>
pi_setting() {
  local key="$1" file="$HOME/.pi/agent/settings.json"
  [[ -f $file ]] || { echo ""; return; }
  python3 -c "
import json, sys
try:
    d = json.load(open('$file'))
    v = d.get('$key', '')
    print('' if v is None else v)
except Exception:
    print('')
" 2>/dev/null
}

# Merge keys into ~/.pi/agent/settings.json without trampling existing entries.
# Usage: pi_set_settings KEY1=val1 KEY2=val2 ...
pi_set_settings() {
  mkdir -p "$HOME/.pi/agent"
  local file="$HOME/.pi/agent/settings.json"

  python3 - "$file" "$@" <<'PY'
import json, sys
path = sys.argv[1]
updates = {}
for kv in sys.argv[2:]:
    k, v = kv.split("=", 1)
    updates[k] = v
try:
    with open(path) as f:
        data = json.load(f)
    if not isinstance(data, dict):
        data = {}
except (FileNotFoundError, json.JSONDecodeError):
    data = {}
data.update(updates)
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
}

# ------------------------------------------------------------------ chrome

install_chrome() {
  if chrome_installed; then
    ok "google-chrome already installed"
    return
  fi

  if ! command_exists yay; then
    fail "yay not found. Install an AUR helper first (e.g. 'pacman -S yay')."
  fi

  echo "Installing $CHROME_PKG from the AUR..."
  # --needed skips reinstalls, --noconfirm keeps the script unattended. We
  # bypass yay's source build when -bin is available; google-chrome itself
  # is the official prebuilt package, so no compile time.
  yay -S --needed --noconfirm "$CHROME_PKG"

  if chrome_installed; then
    ok "google-chrome installed"
  else
    fail "google-chrome install reported success but binary is missing"
  fi
}

# ------------------------------------------------------------------ ollama

install_ollama() {
  if ollama_installed; then
    ok "ollama already installed"
  else
    if ! command_exists pacman; then
      fail "pacman not found. This installer targets Arch/Omarchy."
    fi

    # Detect an NVIDIA GPU and prefer ollama-cuda when present, falling back to
    # the generic CPU build otherwise. The upstream ollama.com install script
    # does the same autodetect; doing it here means the package is replaceable
    # later through pacman instead of a manual /usr/local/bin write.
    local pkg="$OLLAMA_PKG"
    if lspci 2>/dev/null | grep -qi 'nvidia' && pacman -Si "$OLLAMA_CUDA_PKG" >/dev/null 2>&1; then
      pkg="$OLLAMA_CUDA_PKG"
      note "NVIDIA GPU detected — using $OLLAMA_CUDA_PKG"
    fi

    echo "Installing $pkg from [extra] (Arch's repackage of the ollama.com build)..."
    # Prefer sudo -n (non-interactive) when available; fall back to a plain
    # pacman call which will only work as root. The script stays unattended
    # either way — the user runs it from a context where they can elevate.
    if command_exists sudo && sudo -n true 2>/dev/null; then
      sudo pacman -S --needed --noconfirm "$pkg"
    else
      pacman -S --needed --noconfirm "$pkg"
    fi

    if ! ollama_installed; then
      fail "ollama install reported success but binary is missing"
    fi
    ok "ollama installed"
  fi

  # Make sure the ollama service is running so pi can reach it. Enable + start
  # in one shot; --now is harmless if the unit is already active.
  if command_exists systemctl; then
    local started=0
    if command_exists sudo && sudo -n true 2>/dev/null; then
      sudo systemctl enable --now ollama.service 2>/dev/null && started=1
    fi
    if (( !started )); then
      systemctl enable --now ollama.service 2>/dev/null && started=1
    fi
    if (( started )); then
      ok "ollama.service enabled and started"
    else
      warn "could not enable ollama.service — start it manually before using pi"
    fi
  fi
}

# ------------------------------------------------------------------ scaling

apply_scaling() {
  if ! command_exists omarchy-hyprland-monitor-scaling; then
    warn "omarchy-hyprland-monitor-scaling not found — skipping scaling step"
    return
  fi

  if ! command_exists hyprctl; then
    warn "hyprctl not found — skipping scaling step"
    return
  fi

  local current
  current="$(omarchy-hyprland-monitor-scaling 2>/dev/null || true)"
  if [[ $current == "$SCALE" ]]; then
    ok "Hyprland scaling already $SCALE"
    return
  fi

  echo "Setting Hyprland scaling to $SCALE..."
  if omarchy-hyprland-monitor-scaling "$SCALE"; then
    ok "Hyprland scaling set to $SCALE (persisted in ~/.config/hypr/monitors.lua)"
  else
    warn "failed to set Hyprland scaling — run 'omarchy-hyprland-monitor-scaling $SCALE' manually"
  fi
}

# ------------------------------------------------------------------ pi

install_pi() {
  if ! command_exists mise; then
    warn "mise not found — install mise first (e.g. 'pacman -S mise' or https://mise.jdx.dev)"
    return
  fi

  if mise ls pi 2>/dev/null | grep -q pi; then
    ok "pi already installed via mise"
  else
    echo "Installing pi via mise ($PI_VERSION)..."
    mise use -g "pi@$PI_VERSION"
    ok "pi installed via mise"
  fi

  # Configure the Ollama provider and model. Pi reads this from
  # ~/.pi/agent/settings.json; we preserve any other keys the user has set.
  local current_provider current_model
  current_provider="$(pi_setting defaultProvider)"
  current_model="$(pi_setting defaultModel)"

  if [[ $current_provider == "$PI_PROVIDER" && $current_model == "$PI_MODEL" ]]; then
    ok "pi already configured: $PI_PROVIDER / $PI_MODEL"
  else
    echo "Configuring pi: defaultProvider=$PI_PROVIDER, defaultModel=$PI_MODEL"
    pi_set_settings "defaultProvider=$PI_PROVIDER" "defaultModel=$PI_MODEL"
    ok "pi settings written to ~/.pi/agent/settings.json"
  fi
}

# ------------------------------------------------------------------ main

echo "==> System prerequisites"
install_chrome
echo
install_ollama
echo
install_pi

if (( APPLY )); then
  echo
  echo "==> Display"
  apply_scaling
else
  echo
  echo "==> Display (skipped; pass --apply to set Hyprland scaling now)"
fi

echo
echo "Done."
local_chrome=""
command_exists google-chrome-stable && local_chrome="google-chrome-stable"
command_exists google-chrome && local_chrome="${local_chrome:+$local_chrome, }google-chrome"
if [[ -z $local_chrome ]]; then
  command_exists chromium && local_chrome="chromium" || local_chrome="not installed"
fi
echo "  • Chrome:       $local_chrome"
echo "  • Ollama:       $(command_exists ollama && echo installed || echo 'not installed')"
echo "  • Hyprland scaling: $(command_exists omarchy-hyprland-monitor-scaling && omarchy-hyprland-monitor-scaling 2>/dev/null || echo 'unknown')"
echo "  • Pi provider:  $(pi_setting defaultProvider)"
echo "  • Pi model:     $(pi_setting defaultModel)"
