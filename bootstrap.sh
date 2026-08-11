#!/usr/bin/env bash
# bootstrap.sh — the whole workspace in one command, on a fresh Arch
# install (base system per docs/arch-install.md):
#
#   curl -fsSL https://raw.githubusercontent.com/nafud/dotfiles/main/bootstrap.sh | bash
#
# Clones the repo over HTTPS (no SSH key needed to receive) into ~/dotfiles
# — or fast-forwards an existing clone — then hands off to setup.sh,
# which is idempotent. The push URL is set to SSH so commits go out
# authenticated once the key from the backup is restored. sudo prompts
# work as usual: sudo reads /dev/tty, so piping this script into bash
# does not get in its way.
set -euo pipefail

REPO_DIR="$HOME/dotfiles"
REPO_HTTPS="https://github.com/nafud/dotfiles.git"
REPO_SSH="git@github.com:nafud/dotfiles.git"

[ "$(id -u)" -eq 0 ] && { echo "run as your user, not root" >&2; exit 1; }
command -v git >/dev/null || sudo pacman -S --needed --noconfirm git

if [ -d "$REPO_DIR/.git" ]; then
    git -C "$REPO_DIR" pull --ff-only
else
    git clone "$REPO_HTTPS" "$REPO_DIR"
    git -C "$REPO_DIR" remote set-url --push origin "$REPO_SSH"
fi

exec bash "$REPO_DIR/setup.sh"
