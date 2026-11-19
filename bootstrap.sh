#!/usr/bin/env bash
# Takes a fresh machine from nothing to a built config. Safe to re-run.
# After it finishes, use ./rebuild.sh for every later change.
#
# Usage: ./bootstrap.sh --role desktop|server
#   desktop  a machine you sit at (macOS: AeroSpace, Flick, GUI apps;
#            Omarchy: Omarchy's desktop plus omarchy/packages.txt)
#   server   headless / always-on, CLI only
set -euo pipefail

[ "$(id -u)" != 0 ] || { echo "$(basename "$0"): run as your user, not root/sudo" >&2; exit 1; }
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
die() { echo "bootstrap: $*" >&2; exit 1; }
usage() { sed -n '2,9s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"; }

role=
while [ $# -gt 0 ]; do
  case "$1" in
    --role) role="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
case "$role" in desktop|server) ;; *) usage >&2; exit 2 ;; esac

echo "==> Nix (Determinate)"
if command -v nix >/dev/null 2>&1; then
  echo "    already installed"
else
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
    | sh -s -- install --no-confirm
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

echo "==> This repo at ~/.dotfiles"
# Every config link resolves through ~/.dotfiles. Clone straight there; a
# clone elsewhere gets a symlink (an existing real directory is left alone).
if [ "$DIR" != "$(cd "$HOME/.dotfiles" 2>/dev/null && pwd -P)" ]; then
  [ -e "$HOME/.dotfiles" ] && [ ! -L "$HOME/.dotfiles" ] && die "~/.dotfiles exists and is not this repo"
  ln -sfn "$DIR" "$HOME/.dotfiles"
fi

echo "==> zsh as login shell"
# From the system package manager, so it is listed in /etc/shells.
if [ "$(uname -s)" = Linux ] && ! command -v zsh >/dev/null 2>&1; then
  if command -v pacman >/dev/null 2>&1; then sudo pacman -S --needed --noconfirm zsh
  elif command -v apt-get >/dev/null 2>&1; then sudo apt-get update -q && sudo apt-get install -yq zsh
  elif command -v dnf >/dev/null 2>&1; then sudo dnf install -y zsh
  else die "install zsh with your package manager, then re-run"
  fi
fi
zsh="$(command -v zsh)"
case "$(uname -s)" in
  Darwin) current="$(dscl . -read "/Users/$(id -un)" UserShell | awk '{print $2}')" ;;
  *) current="$(getent passwd "$(id -un)" | cut -d: -f7)" ;;
esac
if [ "$(basename "$current")" != zsh ]; then
  sudo chsh -s "$zsh" "$(id -un)"
else
  echo "    already zsh"
fi

echo "==> Machine-local files (never committed; created only if missing)"
starter() {  # starter <path> <mode> <content>
  [ -e "$1" ] && { echo "    keep   $1"; return; }
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "$3" > "$1"; chmod "$2" "$1"
  echo "    create $1"
}
starter "$HOME/.config/git/local" 644 '# Machine-local git identity (included by ~/.config/git/config).
# [user]
#   name = Your Name
#   email = you@example.com
#   signingkey = ~/.ssh/id_ed25519.pub
#
# A second profile, chosen by remote URL (e.g. an ssh host alias for work):
# [includeIf "hasconfig:remote.*.url:work-github:*/**"]
#   path = ~/.config/git/work'
starter "$HOME/.ssh/config.local" 600 '# Machine-local ssh config, included first by ~/.ssh/config.
# Hosts, users, IPs and IdentityFile lines go here, never in the repo.'
starter "$HOME/.zshrc.local" 600 '# Machine-local zsh: secrets and env. Sourced last by ~/.zshrc.'
starter "$HOME/.config/dotfiles/deny.txt" 600 '# Extra patterns check.sh refuses to commit (one ERE per line):
# names, emails and hosts too private to list in the public check.sh.'

exec "$DIR/rebuild.sh" --role "$role"
