#!/bin/bash
# Install everything in this repo:
#   - Netrunner Omarchy theme
#   - odessa.agents Omarchy bar plugin
#   - Pi usage collector wrapper + scripts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/install-theme.sh"
echo
"$SCRIPT_DIR/install-plugin.sh"

echo
echo "Install complete. Next steps:"
echo "  omarchy theme set netrunner"
echo "  omarchy plugin enable odessa.agents --section right"
echo "  omarchy restart shell"
