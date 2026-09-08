#!/bin/bash
#
# Installer for latch.
#
# One-liner (no clone needed):
#   curl -fsSL https://raw.githubusercontent.com/ashcbrd/latch/main/install.sh | bash
#
# From a clone:
#   ./install.sh [--no-sudoers]
#
set -euo pipefail

REPO="ashcbrd/latch"
BRANCH="main"
RAW_BASE="https://raw.githubusercontent.com/$REPO/$BRANCH"

BIN_DIR="/usr/local/bin"
DEST="$BIN_DIR/latch"
SUDOERS_FILE="/etc/sudoers.d/latch"
PMSET="/usr/bin/pmset"

WANT_SUDOERS=1
for arg in "$@"; do
  case "$arg" in
    --no-sudoers) WANT_SUDOERS=0 ;;
    *) printf 'unknown option: %s\n' "$arg" >&2; exit 1 ;;
  esac
done

if [ -t 1 ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_GREEN=""; C_YELLOW=""; C_RED=""
fi

step() { printf '  %s\n' "$*"; }
ok()   { printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
die()  { printf '\n%serror:%s %s\n\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

cleanup() { [ -n "${TMP_DIR:-}" ] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT

printf '\n%slatch installer%s\n\n' "$C_BOLD" "$C_RESET"

# ------------------------------------------------------------ preflight

[ "$(uname -s)" = "Darwin" ]  || die "latch is macOS-only (found $(uname -s))"
[ -x "$PMSET" ]               || die "$PMSET not found - is this really macOS?"

USER_NAME="$(id -un)"
step "user               $USER_NAME"
step "macOS              $(sw_vers -productVersion)"
step "architecture       $(uname -m)"

# When piped from curl there is no script on disk, so BASH_SOURCE is not a
# usable path. Fall back to downloading the payload in that case.
SRC=""
LINK_MODE=0
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]:-}" ]; then
  MAYBE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [ -f "$MAYBE_DIR/latch" ]; then
    SRC="$MAYBE_DIR/latch"
    LINK_MODE=1
    step "source             local clone"
  fi
fi

if [ -z "$SRC" ]; then
  step "source             $RAW_BASE"
  command -v curl >/dev/null 2>&1 || die "curl is required"
  TMP_DIR="$(mktemp -d)"
  SRC="$TMP_DIR/latch"
  if ! curl -fsSL "$RAW_BASE/latch" -o "$SRC"; then
    die "could not download latch from $RAW_BASE/latch
  If the repository is private, raw.githubusercontent.com returns 404.
  Clone it instead:  gh repo clone $REPO && cd latch && ./install.sh"
  fi
  # Guard against a 404 page or truncated download being installed as a binary.
  head -1 "$SRC" | grep -q '^#!/bin/bash' || die "downloaded file is not the latch script"
  grep -q 'cmd_watchdog' "$SRC"           || die "downloaded file looks incomplete"
  bash -n "$SRC" 2>/dev/null              || die "downloaded script failed a syntax check"
fi
printf '\n'

# --------------------------------------------------------------- binary

chmod +x "$SRC"

if [ ! -d "$BIN_DIR" ]; then
  step "creating $BIN_DIR (needs sudo)"
  sudo mkdir -p "$BIN_DIR"
fi

SUDO_BIN=""
[ -w "$BIN_DIR" ] || SUDO_BIN="sudo"

if [ "$LINK_MODE" -eq 1 ]; then
  # Symlink from a clone so `git pull` updates the installed command.
  $SUDO_BIN ln -sf "$SRC" "$DEST"
  ok "linked $DEST -> $SRC"
else
  # Copy, because the download lives in a temp dir that is about to vanish.
  $SUDO_BIN install -m 0755 "$SRC" "$DEST"
  ok "installed $DEST"
fi

# -------------------------------------------------------------- sudoers

if [ "$WANT_SUDOERS" -eq 1 ]; then
  printf '\n  %slatch needs sudo to change power settings.%s\n' "$C_BOLD" "$C_RESET"
  printf '  %sInstalling a rule so it never asks for your password again.%s\n' "$C_DIM" "$C_RESET"
  printf '  %sScoped to 4 exact pmset commands. Skip with --no-sudoers.%s\n\n' "$C_DIM" "$C_RESET"

  TMP_SUDOERS="$(mktemp)"
  cat >"$TMP_SUDOERS" <<SUDOERS
# Installed by latch (https://github.com/$REPO)
# Allows $USER_NAME to toggle only these exact power settings without a
# password. Remove with: sudo rm $SUDOERS_FILE
$USER_NAME ALL=(root) NOPASSWD: $PMSET -a disablesleep 1, $PMSET -a disablesleep 0, $PMSET -a lowpowermode 1, $PMSET -a lowpowermode 0
SUDOERS

  # Validate BEFORE installing. A malformed sudoers file can lock the user
  # out of sudo entirely, so this check is not optional.
  if ! sudo visudo -c -f "$TMP_SUDOERS" >/dev/null 2>&1; then
    sudo visudo -c -f "$TMP_SUDOERS" || true
    rm -f "$TMP_SUDOERS"
    die "refusing to install an invalid sudoers file"
  fi

  sudo install -m 0440 -o root -g wheel "$TMP_SUDOERS" "$SUDOERS_FILE"
  rm -f "$TMP_SUDOERS"
  ok "installed $SUDOERS_FILE ${C_DIM}(validated)${C_RESET}"

  if sudo -n "$PMSET" -g >/dev/null 2>&1; then
    ok "passwordless pmset confirmed"
  else
    printf '  %s!%s rule installed but not active in this shell yet\n' "$C_YELLOW" "$C_RESET"
  fi
else
  step "skipping sudoers rule - latch will prompt for your password"
fi

# ----------------------------------------------------------- verify

printf '\n'
if "$DEST" version >/dev/null 2>&1; then
  ok "$("$DEST" version) is working"
else
  die "installed, but '$DEST version' did not run"
fi

# ----------------------------------------------------------------- done

printf '\n%sReady.%s\n\n' "$C_BOLD" "$C_RESET"
printf '  %slatch%s          arm it, then close the lid\n' "$C_BOLD" "$C_RESET"
printf '  %slatch --cool%s   same, but runs cooler on battery\n' "$C_BOLD" "$C_RESET"
printf '  %slatch status%s   check what is active\n' "$C_BOLD" "$C_RESET"
printf '  %slatch off%s      restore normal sleep\n\n' "$C_BOLD" "$C_RESET"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) printf '  %sNote:%s %s is not on your PATH. Add to ~/.zshrc:\n\n    export PATH="%s:$PATH"\n\n' \
       "$C_YELLOW" "$C_RESET" "$BIN_DIR" "$BIN_DIR" ;;
esac
