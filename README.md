# omarchy-files

Personal Omarchy desktop configuration: a custom theme and a custom Pi-aware
agents bar plugin.

## What's included

| Path | What |
|------|------|
| `theme/netrunner/` | Custom Omarchy theme (colors, Neovim/Vscode themes, backgrounds) |
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
./install-theme.sh      # theme + extra backgrounds only
./install-plugin.sh     # plugin + Pi collectors only
./install-extensions.sh # BFL + Pi menu extension and generator command only
```

## Updating

Re-run `./install.sh` after pulling the latest changes. The script replaces
the installed theme, plugin, and collector files, so it is safe to run on a
clean Omarchy install or on top of an existing install.

## Notes

- The Pi collector reads `~/.pi/agent/sessions/*.jsonl`. It produces no output
  until Pi has recorded sessions.
- `omarchy-agent-usage-update` is installed to `~/.local/bin` and, when the
  Pi tool's bin directory exists, also to `~/.pi/agent/bin`. This ensures the
  wrapper shadows the packaged Omarchy updater and refreshes the Pi record
  automatically.
- Make sure `~/.local/bin` is on PATH (Omarchy includes it by default).
