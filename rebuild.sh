#!/usr/bin/env bash
# Builds and activates this machine's config. Run after every change or pull.
# Usage: ./rebuild.sh [--role desktop|server]
#   --role   (re)sets this machine's role; bootstrap.sh passes it. Otherwise
#            the role in ~/.config/dotfiles/machine.nix is kept.
# Omarchy and mise are re-detected on every run, so installing mise later
# just works.
set -euo pipefail
# Never as root: ~ would be /root and the config would land on the wrong user.
# The script calls sudo itself where needed.
[ "$(id -u)" != 0 ] || { echo "$(basename "$0"): run as your user, not root/sudo" >&2; exit 1; }
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
die() { echo "rebuild: $*" >&2; exit 1; }

machine="$HOME/.config/dotfiles"
role=
while [ $# -gt 0 ]; do
  case "$1" in
    --role) role="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,7s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done
if [ -z "$role" ]; then
  [ -r "$machine/machine.nix" ] || die "no $machine/machine.nix; run ./bootstrap.sh --role ..."
  role="$(sed -n 's/^ *role = "\(.*\)";/\1/p' "$machine/machine.nix")"
fi
case "$role" in desktop|server) ;; *) die "role must be desktop or server, got '$role'" ;; esac

case "$(uname -s)" in Darwin) os=darwin ;; Linux) os=linux ;; *) die "unsupported OS $(uname -s)" ;; esac
case "$(uname -m)" in arm64|aarch64) arch=aarch64 ;; x86_64) arch=x86_64 ;; *) die "unsupported CPU $(uname -m)" ;; esac
omarchy=false; [ "$os" = linux ] && [ -d /usr/share/omarchy ] && omarchy=true
mise=false; command -v mise >/dev/null 2>&1 && mise=true

# Machine identity: never committed. The only writer of this file.
mkdir -p "$machine"
cat > "$machine/machine.nix" <<NIX
{
  role = "$role";
  user = "$(id -un)";
  home = "$HOME";
  system = "$arch-$os";
  omarchy = $omarchy;
  mise = $mise;
}
NIX
echo "rebuild: $role on $arch-$os (omarchy=$omarchy, mise=$mise)"

# Commit hooks run ./check.sh (public-safety scan). Commits here are public:
# author them as the GitHub noreply address.
git -C "$DIR" config core.hooksPath .githooks
git -C "$DIR" config user.email 237175+jmdfm@users.noreply.github.com

# Omarchy: extra system packages (install-only) and their services.
if [ "$omarchy" = true ]; then
  mapfile -t pkgs < <(sed 's/#.*//; s/[[:space:]]//g; /^$/d' "$DIR/omarchy/packages.txt")
  missing=()
  for p in "${pkgs[@]}"; do pacman -Qq "$p" >/dev/null 2>&1 || missing+=("$p"); done
  if [ ${#missing[@]} -gt 0 ]; then
    echo "rebuild: pacman: ${missing[*]}"
    sudo pacman -S --needed --noconfirm "${missing[@]}"
  fi
  # System services those packages need running (enable-only).
  mapfile -t units < <(sed 's/#.*//; s/[[:space:]]//g; /^$/d' "$DIR/omarchy/services.txt")
  for u in "${units[@]}"; do
    systemctl is-enabled --quiet "$u" 2>/dev/null && continue
    echo "rebuild: enabling $u"
    sudo systemctl enable --now "$u"
  done
fi

args=(--override-input machine "path:$machine")
# sudo resets PATH, so resolve nix first.
# Shells that skipped the Nix profile (agent shells, cron) still build.
command -v nix >/dev/null || PATH="/nix/var/nix/profiles/default/bin:$PATH"
nix="$(command -v nix)" || { echo "rebuild: nix not found (run bootstrap.sh)" >&2; exit 1; }
case "$os" in
  darwin)
    # The flake's pinned darwin-rebuild: works on a fresh Mac too.
    sudo "$nix" run "$DIR#darwin-rebuild" -- switch --flake "$DIR#default" "${args[@]}"
    "$DIR/brew-drift.sh"
    ;;
  linux)
    out="$("$nix" build --no-link --print-out-paths "$DIR#homeConfigurations.default.activationPackage" "${args[@]}")"
    # A real file where home-manager wants a link is moved aside, not fatal
    # (same as home-manager.backupFileExtension on macOS).
    HOME_MANAGER_BACKUP_EXT=hm-backup "$out/activate"
    ;;
esac

# Signing is on everywhere: without a key every commit fails.
if ! git config --file "$HOME/.config/git/local" user.signingkey >/dev/null 2>&1; then
  printf '\033[33mrebuild: no user.signingkey in ~/.config/git/local; git commits will fail to sign\033[0m\n' >&2
fi
