#!/bin/bash
#
# Uninstaller for latch. Restores normal sleep behaviour first, so the
# machine is never left with sleep permanently disabled and no tool to fix it.
#
set -euo pipefail

BIN_DIR="/usr/local/bin"
DEST="$BIN_DIR/latch"
SUDOERS_FILE="/etc/sudoers.d/latch"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/latch"

if [ -t 1 ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_GREEN=$'\033[32m'
else
  C_RESET=""; C_BOLD=""; C_GREEN=""
fi
ok() { printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }

printf '\n%slatch uninstaller%s\n\n' "$C_BOLD" "$C_RESET"

# Restore power settings while the tool is still available to do it.
if command -v latch >/dev/null 2>&1; then
  latch off >/dev/null 2>&1 || true
  ok "restored normal sleep behaviour"
fi

# Belt and braces: clear the setting directly in case the script was broken.
if /usr/bin/pmset -g | grep -Eq 'SleepDisabled[[:space:]]+1'; then
  sudo /usr/bin/pmset -a disablesleep 0
  ok "cleared lingering disablesleep"
fi

[ -L "$DEST" ] || [ -f "$DEST" ] && { sudo rm -f "$DEST"; ok "removed $DEST"; }
[ -f "$SUDOERS_FILE" ] && { sudo rm -f "$SUDOERS_FILE"; ok "removed $SUDOERS_FILE"; }
[ -d "$STATE_DIR" ] && { rm -rf "$STATE_DIR"; ok "removed $STATE_DIR"; }

printf '\n%sUninstalled.%s The repo directory itself was left alone.\n\n' "$C_BOLD" "$C_RESET"
