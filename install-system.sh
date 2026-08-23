#!/bin/bash
# Install the system-level pieces the omarchy-files repo assumes are present:
#   - google-chrome (AUR) for browsing
#   - ollama (Arch extra, which is the ollama.com binary repackaged) for local models
#   - Hyprland display scaling set to 1.25 (writes via omarchy-hyprland-monitor-scaling
#     so the displays widget stays in sync and the value survives reboots)
#   - pi via mise, with ollama as the default provider and minimax-m3:cloud as the
#     default model
#   - github-cli (gh) from [extra], configured to launch google-chrome for the
#     `gh auth login --web` flow instead of falling back to chromium
#   - tailscale from [extra] (mesh VPN), with tailscaled.service enabled and
#     the current device added to the tailnet
#   - interactive first-run flows (only when --apply is passed): launch Chrome
#     once so password managers / OAuth logins can be completed, sign in to
#     ollama.com, run `gh auth login --web`, and run `ollama launch pi --config`
#     so the ollama provider in pi is wired up with the web-search/fetch tools
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
GH_PKG="github-cli"
TAILSCALE_PKG="tailscale"
SCALE="1.25"
PI_VERSION="latest"
PI_PROVIDER="ollama"
PI_MODEL="minimax-m3:cloud"
KITTY_PKG="kitty"

note() { printf '  • %s\n' "$*"; }
ok() { printf '  ✓ %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }
fail() { printf '  ✗ %s\n' "$*" >&2; exit 1; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

# Install one or more pacman packages. Prefers sudo -n (non-interactive) when
# available, so a single root shell can re-run this script unattended; falls
# back to a plain pacman call which only works as root. Stays silent on
# already-installed packages via --needed and accepts the usual pacman flags.
pacman_install() {
  if ! command_exists pacman; then
    fail "pacman not found. This installer targets Arch/Omarchy."
  fi
  if command_exists sudo && sudo -n true 2>/dev/null; then
    sudo pacman -S --needed --noconfirm "$@"
  else
    pacman -S --needed --noconfirm "$@"
  fi
}

# Run a command with sudo when it's available and the user can elevate
# non-interactively. When sudo -n fails (no passwordless sudo configured) the
# command is run directly — this is fine for the common case where the script
# is already executing as root.
maybe_sudo() {
  if command_exists sudo && sudo -n true 2>/dev/null; then
    sudo "$@"
  else
    "$@"
  fi
}

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

# Have we already installed github-cli (gh binary or package)?
gh_installed() {
  command_exists gh || pacman -Qq "$GH_PKG" >/dev/null 2>&1
}

# Have we already installed tailscale?
tailscale_installed() {
  command_exists tailscale || pacman -Qq "$TAILSCALE_PKG" >/dev/null 2>&1
}

# Is gh already authenticated to github.com? Returns 0 on success, 1 otherwise.
# Used to decide whether to launch `gh auth login --web` interactively.
gh_authed() {
  command_exists gh || return 1
  gh auth status --hostname github.com >/dev/null 2>&1
}

# Is ollama already signed in? We probe the public key file (the ollama CLI
# drops it under ~/.ollama when signin completes) instead of talking to the
# daemon — `ollama signin` is interactive and we only want to know whether
# it has been run before, not whether the daemon is reachable.
ollama_signed_in() {
  local keyfile="$HOME/.ollama/id_ed25519"
  [[ -f $keyfile ]]
}

# Is the current device already in a tailnet? `tailscale status` exits 0 when
# the daemon is logged in to an account, non-zero (typically exit 1) when it
# is running but un-authenticated. Tailscaled may not be running at all on
# a fresh install, in which case we treat the device as un-joined.
tailscale_joined() {
  command_exists tailscale || return 1
  command_exists tailscaled || return 1
  pgrep -x tailscaled >/dev/null 2>&1 || return 1
  tailscale status >/dev/null 2>&1
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
    pacman_install "$pkg"

    if ! ollama_installed; then
      fail "ollama install reported success but binary is missing"
    fi
    ok "ollama installed"
  fi

  # Make sure the ollama service is running so pi can reach it. Enable + start
  # in one shot; --now is harmless if the unit is already active.
  if command_exists systemctl; then
    if maybe_sudo systemctl enable --now ollama.service 2>/dev/null; then
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

# ------------------------------------------------------------------ kitty

install_kitty() {
  # Kitty is the default terminal in this Omarchy install. We install the
  # package when missing, drop Omarchy's default config if there isn't one
  # yet (so a fresh machine still gets font/keybinding defaults), and then
  # set kitty as the default terminal so Super+Return, omarchy-launch-terminal,
  # and xdg-terminal-exec all open it.
  if ! command_exists kitty; then
    echo "Installing $KITTY_PKG from [extra]..."
    if ! pacman_install "$KITTY_PKG"; then
      warn "could not install kitty — install manually before continuing"
      return
    fi
  fi

  if ! command_exists kitty; then
    warn "kitty install reported success but binary is missing"
    return
  fi
  ok "kitty installed"

  # Drop the default Omarchy kitty.conf on first install so the font, padding,
  # keybindings, and the theme include are all in place. A user-customised
  # kitty.conf is left alone — only an empty/missing directory gets seeded.
  local kitty_dir="$HOME/.config/kitty"
  if [[ ! -f $kitty_dir/kitty.conf ]]; then
    mkdir -p "$kitty_dir"
    if [[ -f $OMARCHY_PATH/config/kitty/kitty.conf ]]; then
      cp "$OMARCHY_PATH/config/kitty/kitty.conf" "$kitty_dir/kitty.conf"
      ok "seeded ~/.config/kitty/kitty.conf from Omarchy defaults"
    fi
  fi

  # Make kitty the default terminal. omarchy default terminal writes
  # ~/.config/xdg-terminals.list and notifies the user; the next
  # omarchy-launch-terminal / xdg-terminal-exec call will then open kitty.
  if command_exists omarchy-default-terminal; then
    local current_default
    current_default="$(omarchy-default-terminal 2>/dev/null || true)"
    if [[ $current_default == "kitty" ]]; then
      ok "kitty already set as the default terminal"
    else
      echo "Setting kitty as the default terminal..."
      omarchy-default-terminal kitty >/dev/null
      ok "kitty is now the default terminal (current: $current_default → kitty)"
    fi
  else
    warn "omarchy-default-terminal not found — set kitty manually if needed"
  fi
}

# ------------------------------------------------------------------ chrome login

# Open google-chrome once so the user can sign in to password managers, OAuth
# providers, and any other accounts the rest of this script will need (gh auth,
# ollama signin, etc.). This is only done under --apply; without --apply the
# script stays non-interactive and just prints a reminder instead.
#
# We pick the stable binary when available (google-chrome-stable) and fall
# through to plain `google-chrome` if that's what the AUR package exposed. The
# launch is fire-and-forget — we don't wait for the window to close, since
# the user keeps working in it (and other terminals) in parallel.
launch_chrome_for_login() {
  if ! chrome_installed; then
    warn "google-chrome not installed yet — skipping Chrome login launch"
    return
  fi

  local chrome_bin=""
  if command_exists google-chrome-stable; then
    chrome_bin="google-chrome-stable"
  elif command_exists google-chrome; then
    chrome_bin="google-chrome"
  fi

  if [[ -z $chrome_bin ]]; then
    warn "google-chrome binary not on PATH — skipping Chrome login launch"
    return
  fi

  echo "Launching google-chrome so you can sign in to password managers / OAuth..."
  # `>/dev/null 2>&1 &` detaches so the installer can keep going. --no-first-run
  # suppresses the "make Chrome your default browser" prompt that would otherwise
  # steal focus on a fresh install.
  ( "$chrome_bin" --no-first-run >/dev/null 2>&1 & )
  ok "google-chrome launched — sign in to whatever you need, then come back here"
}

# ------------------------------------------------------------------ gh

install_gh() {
  if gh_installed; then
    ok "github-cli already installed"
  else
    echo "Installing $GH_PKG from [extra]..."
    pacman_install "$GH_PKG"
    if ! gh_installed; then
      fail "github-cli install reported success but gh binary is missing"
    fi
    ok "github-cli installed"
  fi

  # Configure gh to launch google-chrome for `gh auth login --web`. Without
  # this, gh falls back to xdg-open → chromium, which won't have the user's
  # saved passwords / logged-in sessions. We set the browser unconditionally
  # because it's idempotent and cheap; re-running the script is a no-op.
  if command_exists gh; then
    local current_browser
    current_browser="$(gh config get browser 2>/dev/null || true)"
    if [[ $current_browser == *"google-chrome"* ]]; then
      ok "gh already configured to use google-chrome"
    else
      gh config set browser "google-chrome" >/dev/null
      ok "gh configured to use google-chrome (was: '${current_browser:-unset}')"
    fi
  fi
}

# Run `gh auth login --web` interactively so the OAuth flow pops Chrome (which
# we just configured) and the user can approve. Only invoked under --apply
# and only when no existing credentials are found.
auth_gh() {
  if ! command_exists gh; then
    warn "gh not installed — skipping gh auth login"
    return
  fi

  if gh_authed; then
    ok "gh already authenticated to github.com"
    return
  fi

  echo "Running 'gh auth login --web' — Chrome should open for OAuth..."
  echo "  (use the GitHub.com / HTTPS / web options)"
  # --web forces the browser flow (no need to paste a token), --git-protocol
  # https sets the default clone URL scheme without an extra prompt. We don't
  # --skip-ssh-key so gh can offer to upload an existing key if one is present.
  if gh auth login --web --git-protocol https; then
    ok "gh authenticated to github.com"
  else
    warn "gh auth login did not complete — run it manually before using gh"
  fi
}

# ------------------------------------------------------------------ ollama signin

# Sign in to ollama.com so the local daemon can use cloud models and private
# registry pulls. `ollama signin` is interactive — it prints a URL and the
# user has to open it in their browser. We only invoke it under --apply and
# only when no public key is on disk yet.
auth_ollama() {
  if ! command_exists ollama; then
    warn "ollama not installed — skipping ollama signin"
    return
  fi

  if ollama_signed_in; then
    ok "ollama already signed in (found ~/.ollama/id_ed25519)"
    return
  fi

  echo "Running 'ollama signin' — it'll print a URL; open it in google-chrome..."
  if ollama signin; then
    ok "ollama signed in"
  else
    warn "ollama signin did not complete — run 'ollama signin' manually before pulling cloud models"
  fi
}

# Wire the ollama provider into pi with web tools. `ollama launch pi --config`
# is the official way to (re)configure pi to use ollama: it writes the
# ~/.pi/agent/models.json block and installs/updates the @ollama/pi-web-search
# extension so pi can call web_search/web_fetch when the user asks it to.
# We do not launch an interactive pi session here — that would block the
# installer. Use `ollama launch pi` later (no --config) to actually start pi.
setup_pi_via_ollama() {
  if ! command_exists ollama; then
    warn "ollama not installed — skipping ollama launch pi --config"
    return
  fi

  echo "Running 'ollama launch pi --config' to wire ollama into pi (incl. web tools)..."
  if ollama launch pi --config; then
    ok "pi configured for ollama via 'ollama launch pi --config'"
  else
    warn "'ollama launch pi --config' did not complete — run it manually before using pi"
  fi
}

# ------------------------------------------------------------------ tailscale

install_tailscale() {
  if tailscale_installed; then
    ok "tailscale already installed"
  else
    echo "Installing $TAILSCALE_PKG from [extra]..."
    pacman_install "$TAILSCALE_PKG"
    if ! tailscale_installed; then
      fail "tailscale install reported success but binary is missing"
    fi
    ok "tailscale installed"
  fi

  # Start tailscaled so the user can `tailscale up` straight after. The unit
  # is shipped by the package and is enabled by default; we just make sure
  # it's running on this boot.
  if command_exists systemctl; then
    if maybe_sudo systemctl enable --now tailscaled.service 2>/dev/null; then
      ok "tailscaled.service enabled and started"
    else
      warn "could not enable tailscaled.service — start it manually before 'tailscale up'"
    fi
  fi
}

# `tailscale up` is interactive on first run: it prints a login URL that has
# to be opened in a browser to add the device to the user's tailnet. We only
# invoke it under --apply and only when the device isn't already joined.
auth_tailscale() {
  if ! command_exists tailscale; then
    warn "tailscale not installed — skipping 'tailscale up'"
    return
  fi

  if tailscale_joined; then
    ok "tailscale already joined a tailnet"
    return
  fi

  if ! command_exists systemctl; then
    warn "systemctl not available — run 'sudo tailscale up' manually to add this device"
    return
  fi

  echo "Running 'sudo tailscale up' — it'll print a login URL; open it in google-chrome..."
  if maybe_sudo tailscale up; then
    ok "tailscale: this device added to a tailnet"
  else
    warn "'tailscale up' did not complete — run 'sudo tailscale up' manually to add this device"
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
install_kitty
echo
install_pi

if (( APPLY )); then
  echo
  echo "==> First-run auth flows"
  # Chrome first so the user can sign in to password managers / OAuth in
  # parallel with the remaining prompts. Each subsequent auth step is gated
  # on the relevant service being installed, and each is idempotent — the
  # script can be re-run and the second pass becomes a no-op.
  launch_chrome_for_login
  echo
  auth_ollama
  echo
  install_gh
  auth_gh
  echo
  install_tailscale
  auth_tailscale
  echo
  setup_pi_via_ollama
  echo
  echo "==> Display"
  apply_scaling
else
  echo
  echo "==> First-run auth flows (skipped; pass --apply to run them)"
  echo "  • Launch google-chrome so you can sign in to password managers / OAuth"
  echo "  • ollama signin          (sign in to ollama.com for cloud models)"
  echo "  • gh auth login --web    (uses google-chrome instead of chromium)"
  echo "  • sudo tailscale up      (add this device to your tailnet)"
  echo "  • ollama launch pi --config   (wire ollama into pi with web tools)"
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
gh_status="not installed"
if command_exists gh; then
  if gh_authed; then gh_status="installed, authenticated"
  else gh_status="installed, not authenticated"
  fi
fi
ts_status="not installed"
if command_exists tailscale; then
  if tailscale_joined; then ts_status="installed, joined"
  else ts_status="installed, not joined"
  fi
fi
ollama_status="not installed"
if command_exists ollama; then
  if ollama_signed_in; then ollama_status="installed, signed in"
  else ollama_status="installed, not signed in"
  fi
fi
gh_browser="$(command_exists gh && gh config get browser 2>/dev/null || echo 'unset')"
echo "  • Chrome:              $local_chrome"
echo "  • Ollama:              $ollama_status"
echo "  • Kitty (default):     $(command_exists kitty && (command_exists omarchy-default-terminal && [ "$(omarchy-default-terminal 2>/dev/null)" = kitty ] && echo "installed, default" || echo "installed, not default") || echo 'not installed')"
echo "  • gh:                  $gh_status  (browser: $gh_browser)"
echo "  • Tailscale:           $ts_status"
echo "  • Hyprland scaling:    $(command_exists omarchy-hyprland-monitor-scaling && omarchy-hyprland-monitor-scaling 2>/dev/null || echo 'unknown')"
echo "  • Pi provider:         $(pi_setting defaultProvider)"
echo "  • Pi model:            $(pi_setting defaultModel)"
