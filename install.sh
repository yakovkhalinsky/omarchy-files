#!/bin/bash
# Install everything in this repo:
#   - Netrunner Omarchy theme
#   - odessa.agents Omarchy bar plugin
#   - Pi usage collector wrapper + scripts
#
# Usage: ./install.sh [--apply]
#   --apply  Also set the theme and enable the plugin (default: just print steps)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPLY=0

if (( $# > 0 )) && [[ $1 == --apply ]]; then
  APPLY=1
fi

"$SCRIPT_DIR/install-theme.sh"
echo
"$SCRIPT_DIR/install-plugin.sh"
echo
"$SCRIPT_DIR/install-extensions.sh"

if (( APPLY )); then
  echo
  echo "Applying theme, enabling plugin, and refreshing menu..."
  omarchy theme set netrunner
  omarchy plugin enable odessa.agents --section right
  omarchy menu refresh
  omarchy restart shell
else
  echo
  echo "Install complete. Next steps:"
  echo "  omarchy theme set netrunner"
  echo "  omarchy plugin enable odessa.agents --section right"
  echo "  omarchy menu refresh"
  echo "  omarchy restart shell"
fi