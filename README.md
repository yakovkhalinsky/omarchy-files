# omarchy-files

Personal Omarchy desktop configuration: a custom theme and a custom Pi-aware
agents bar plugin.

## What's included

| Path | What |
|------|------|
| `install-system.sh` | System prerequisites: Chrome (AUR on Omarchy / Homebrew cask on macOS), Ollama, Kitty, Hyprland scaling 1.25 (Omarchy only), Pi via mise, Pi default provider/model, GitHub CLI (`gh`) with `google-chrome` set as its browser, Tailscale (`tailscaled.service` on Linux, GUI app on macOS). Auto-detects the platform. Under `--apply` it also launches Chrome once so password managers / OAuth logins can be completed, runs `ollama signin`, `gh auth login --web`, `sudo tailscale up` (Linux) / opens the Tailscale app (macOS), and `ollama launch pi --config` (which wires the ollama provider into pi together with the web-search/fetch tools). |
| `theme/netrunner/` | Custom Omarchy theme (colors, Neovim/Vscode/Kitty themes, backgrounds) |
| `backgrounds/netrunner/` | Extra per-theme backgrounds |
| `plugin/odessa.agents/` | Custom Omarchy shell plugin (cloned from `omarchy.agents`) with Pi support |
| `bin/omarchy-agent-usage-pi` | Collector that turns Pi JSONL sessions into an agents-panel record |
| `bin/omarchy-agent-usage-update` | Wrapper that calls the real Omarchy updater, then refreshes the Pi record |
| `extensions/omarchy-menu.jsonc` | Omarchy menu entries under **Trigger → BFL** and **Trigger → Pi** |
| `bin/omarchy-bfl-generate` | BFL.ai image generator with optional `--set-bg` |

## Install everything

```bash
git clone https://github.com/yakovkhalinsky/omarchy-files.git
cd omarchy-files
./install.sh --apply
```

`--apply` sets the theme, enables the plugin, and refreshes the menu automatically. Without it the
script just installs the files and prints the commands to apply them.

Alternatively, install the files first and apply manually:

```bash
./install.sh
omarchy theme set netrunner
omarchy plugin enable odessa.agents --section right
omarchy menu refresh
omarchy restart shell
```

## Install components separately

```bash
./install-system.sh    # Chrome + Ollama + scaling + Pi (the system-level bits)
./install-theme.sh      # theme + extra backgrounds only
./install-plugin.sh     # plugin + Pi collectors only
./install-extensions.sh # BFL + Pi menu extension and generator command only
```

`./install-system.sh` and `./install.sh` accept `--apply`; everything else runs immediately.

## Updating

Re-run `./install.sh` after pulling the latest changes. The script replaces
the installed theme, plugin, and collector files, so it is safe to run on a
clean Omarchy install or on top of an existing install.

## Notes

- `install-system.sh` auto-detects the platform: on Linux/Omarchy it uses
  `pacman` (with `sudo` for privilege escalation) and `yay` for the AUR; on
  macOS it uses Homebrew (`brew install` for formulae, `brew install --cask`
  for Chrome and Tailscale). The Omarchy-specific bits (Hyprland scaling,
  `omarchy-default-terminal`, the `~/.config/kitty/kitty.conf` seed) are
  skipped on macOS, and Tailscale sign-in is done through the menu-bar app
  (`open -a Tailscale`) instead of `sudo tailscale up`.
- The Pi collector reads `~/.pi/agent/sessions/*.jsonl`. It produces no output
  until Pi has recorded sessions.
- `omarchy-agent-usage-update` is installed to `~/.local/bin` and, when the
  Pi tool's bin directory exists, also to `~/.pi/agent/bin`. This ensures the
  wrapper shadows the packaged Omarchy updater and refreshes the Pi record
  automatically. When the wrapper is shadowed by `/usr/share/omarchy/bin`,
  `install-plugin.sh` falls back to installing a user systemd timer
  (`omarchy-agent-usage-refresh.timer`) that runs the upstream updater with
  `--except pi` and then writes `pi.json` itself.
- Make sure `~/.local/bin` is on PATH (Omarchy includes it by default).
- `install-system.sh` requires `sudo` (with a configured password OR
  passwordless NOPASSWD) on Linux/Omarchy — when sudo is available but not
  passwordless, the script will prompt for a password at each privileged
  step instead of failing. It is fully idempotent: re-runs are no-ops once
  each component is in place. The Ollama package is `extra/ollama` (or
  `extra/ollama-cuda` when an NVIDIA GPU is detected) — Arch's repackage of
  the same upstream binary that ollama.com's install script drops into
  `/usr/local/bin`. On macOS, Homebrew is required (the script will fail
  with a clear message if it's not installed) and ollama is installed via
  `brew install ollama` — the brew formula provides a LaunchAgent so
  `ollama serve` is started for you at login.
- Under `--apply` the system installer also runs the interactive first-run
  flows in this order: launch Google Chrome (so password managers / OAuth
  can be completed in parallel), `ollama signin`, `gh auth login --web`
  (gh is pre-configured with `google-chrome` as its browser, so the OAuth
  callback lands in the same window), `sudo tailscale up` on Linux / open
  the Tailscale app on macOS, and `ollama launch pi --config` (wires
  ollama into pi and installs the web-search/fetch tools). Each step is
  gated by an idempotency check (`gh auth status`, `~/.ollama/id_ed25519`,
  `tailscale status`), so re-running the installer only re-prompts for
  what's still missing.
- On Omarchy, kitty is installed and set as the default terminal in
  `xdg-terminals.list`, so `Super+Return`, `omarchy-launch-terminal`, and
  any `xdg-terminal-exec` caller all open it. The netrunner theme ships
  its own `kitty.conf` with inline palette + extra padding (16px), 10pt
  font, powerline tab bar in neon green, and a silent visual bell — drop
  into a fresh shell with `omarchy theme set netrunner` (or just re-run
  `./install.sh --apply`).
