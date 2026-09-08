#!/bin/bash
#
# Installer for nosleep.
#
#   ./install.sh              install
#   ./install.sh --no-sudoers install without the passwordless sudo rule
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$REPO_DIR/nosleep"
BIN_DIR="/usr/local/bin"
DEST="$BIN_DIR/nosleep"
SUDOERS_FILE="/etc/sudoers.d/nosleep"
PMSET="/usr/bin/pmset"

WANT_SUDOERS=1
[ "${1:-}" = "--no-sudoers" ] && WANT_SUDOERS=0

if [ -t 1 ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_GREEN=""; C_YELLOW=""; C_RED=""
fi

step() { printf '  %s\n' "$*"; }
ok()   { printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
die()  { printf '%serror:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

printf '\n%snosleep installer%s\n\n' "$C_BOLD" "$C_RESET"

# ------------------------------------------------------------ preflight

[ "$(uname -s)" = "Darwin" ] || die "nosleep is macOS-only (found $(uname -s))"
[ -f "$SRC" ]  || die "cannot find 'nosleep' next to this installer"
[ -x "$PMSET" ] || die "$PMSET not found - is this really macOS?"

USER_NAME="$(id -un)"
step "user               $USER_NAME"
step "macOS              $(sw_vers -productVersion)"
step "architecture       $(uname -m)"
printf '\n'

# --------------------------------------------------------------- binary

chmod +x "$SRC"

if [ ! -d "$BIN_DIR" ]; then
  step "creating $BIN_DIR (needs sudo)"
  sudo mkdir -p "$BIN_DIR"
fi

# Symlink rather than copy so `git pull` updates the installed command.
if [ -w "$BIN_DIR" ]; then
  ln -sf "$SRC" "$DEST"
else
  sudo ln -sf "$SRC" "$DEST"
fi
ok "linked $DEST -> $SRC"

# -------------------------------------------------------------- sudoers

if [ "$WANT_SUDOERS" -eq 1 ]; then
  # Scope the passwordless rule to the four exact pmset invocations nosleep
  # makes. No wildcards: a blanket `pmset *` would be a far wider grant.
  TMP_SUDOERS="$(mktemp)"
  trap 'rm -f "$TMP_SUDOERS"' EXIT

  cat >"$TMP_SUDOERS" <<SUDOERS
# Installed by nosleep (https://github.com/ashcbrd/nosleep)
# Allows $USER_NAME to toggle only these exact power settings without a
# password. Remove with: sudo rm $SUDOERS_FILE
$USER_NAME ALL=(root) NOPASSWD: $PMSET -a disablesleep 1, $PMSET -a disablesleep 0, $PMSET -a lowpowermode 1, $PMSET -a lowpowermode 0
SUDOERS

  # Validate BEFORE installing. A malformed sudoers file can lock the user
  # out of sudo entirely, so this check is not optional.
  if ! sudo visudo -c -f "$TMP_SUDOERS" >/dev/null 2>&1; then
    printf '\n%svalidation failed%s - refusing to install a broken sudoers file:\n\n' "$C_RED" "$C_RESET"
    sudo visudo -c -f "$TMP_SUDOERS" || true
    die "sudoers rule not installed (nosleep will fall back to prompting for a password)"
  fi

  sudo install -m 0440 -o root -g wheel "$TMP_SUDOERS" "$SUDOERS_FILE"
  ok "installed $SUDOERS_FILE ${C_DIM}(validated)${C_RESET}"

  if sudo -n "$PMSET" -g >/dev/null 2>&1; then
    ok "passwordless pmset confirmed"
  else
    printf '  %s!%s rule installed but not yet active in this shell\n' "$C_YELLOW" "$C_RESET"
  fi
else
  step "skipping sudoers rule (nosleep will prompt for your password)"
fi

# ----------------------------------------------------------------- done

printf '\n%sInstalled.%s\n\n' "$C_BOLD" "$C_RESET"
printf '  %snosleep%s          arm it, then close the lid\n' "$C_BOLD" "$C_RESET"
printf '  %snosleep --cool%s   same, but run cooler on battery\n' "$C_BOLD" "$C_RESET"
printf '  %snosleep status%s   check what is active\n' "$C_BOLD" "$C_RESET"
printf '  %snosleep off%s      restore normal sleep\n\n' "$C_BOLD" "$C_RESET"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) printf '  %sNote:%s %s is not on your PATH. Add this to ~/.zshrc:\n\n    export PATH="%s:$PATH"\n\n' \
       "$C_YELLOW" "$C_RESET" "$BIN_DIR" "$BIN_DIR" ;;
esac
