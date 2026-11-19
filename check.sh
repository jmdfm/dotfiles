#!/usr/bin/env bash
# The one gate. This repo is public: nothing that identifies a person, a
# machine, a network or a key may land in it.
#   ./check.sh          scan + build every role (CI, before a push)
#   ./check.sh --fast   scan only (pre-commit hook)
#   ./check.sh --msg F  scan commit message file F (commit-msg hook)
# Extra private patterns (names, work domains, hostnames), one ERE per line:
# ~/.config/dotfiles/deny.txt, machine-local. Patterns only ever get added.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$DIR"

patterns="$(mktemp)"; trap 'rm -f "$patterns"' EXIT
cat > "$patterns" <<'PAT'
tail[0-9a-f]{4,}\.ts\.net
\b100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3}\b
\b(10\.[0-9]{1,3}|192\.168)\.[0-9]{1,3}\.[0-9]{1,3}\b
\+[1-9][0-9]{9,14}\b
(^|[^A-Za-z0-9._-])/(Users|home)/[a-z][a-z0-9._-]*
-----BEGIN [A-Z ]*PRIVATE KEY
^[[:space:]]*(HostName|IdentityFile|User)[[:space:]]+[^=[:space:]]
^[[:space:]]*Host[[:space:]]+[^*=[:space:]]
(hostname|identityFile)[[:space:]]*=[[:space:]]*"[^"]
(matchBlocks|ssh\.settings)\."?[^*"]
ssh-(ed25519|rsa|dss) AAAA
PAT
deny="$HOME/.config/dotfiles/deny.txt"
[ -r "$deny" ] && grep -vE '^\s*(#|$)' "$deny" >> "$patterns"

# Any email address except these placeholders and public no-reply forms.
email='[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}'
allowed_email='(^|:)([0-9]+\+)?[A-Za-z0-9-]+@users\.noreply\.github\.com$|@example\.(com|org|net)$|^(.*:)?git@github\.com$|^(.*:)?noreply@'

fail() { printf '\033[31mcheck: %s\033[0m\n' "$*" >&2; exit 1; }
emails_in() { grep -oE "$email" | grep -vE "$allowed_email" || true; }

if [ "${1:-}" = --msg ]; then
  body="$(grep -vE '^#' "$2")"
  hits="$(printf '%s\n' "$body" | grep -niE -f "$patterns" || true)"
  [ -z "$hits" ] || fail "personal data in the commit message:"$'\n'"$hits"
  hits="$(printf '%s\n' "$body" | emails_in)"
  [ -z "$hits" ] || fail "email address in the commit message:"$'\n'"$hits"
  exit 0
fi

# Commit identity is public too (rebuild.sh sets the GitHub noreply address).
ident="$(git var GIT_AUTHOR_IDENT 2>/dev/null || true)"
if printf '%s\n' "$ident" | grep -qiE -f "$patterns"; then fail "personal data in the commit author: $ident"; fi
[ -z "$(printf '%s\n' "$ident" | sed 's/.*<\(.*\)>.*/\1/' | emails_in)" ] || fail "commit author is not a noreply address: $ident"

# Index content: what the next commit would publish. check.sh itself holds
# the patterns, so it is skipped for the pattern scan.
hits="$(git grep --cached -nIiE -f "$patterns" -- . ':!check.sh' || true)"
[ -z "$hits" ] || fail "personal data in tracked files (use placeholders; see AGENTS.md):"$'\n'"$hits"
hits="$(git grep --cached -nIoE "$email" -- . | grep -vE "$allowed_email" || true)"
[ -z "$hits" ] || fail "email address in tracked files:"$'\n'"$hits"
# Keys and local files must never be tracked, whatever their content.
hits="$(git ls-files --cached | grep -E '(^|/)(id_[a-z0-9_]+(\.pub)?|[^/]*\.(pem|key|p12)|allowed_signers|[^/]*\.local|machine\.nix|deny\.txt)$' | grep -v '^stub/machine/machine\.nix$' || true)"
[ -z "$hits" ] || fail "key or machine-local file tracked:"$'\n'"$hits"
[ "${1:-}" = --fast ] && exit 0

echo "check: building every role"
case "$(uname -s)" in
  Darwin)
    nix build --no-link .#darwinConfigurations.ci-mac-desktop.system .#darwinConfigurations.ci-mac-server.system
    for c in ci-linux ci-omarchy; do nix eval --raw ".#homeConfigurations.$c.activationPackage.drvPath" >/dev/null; done
    ;;
  Linux)
    nix build --no-link .#homeConfigurations.ci-linux.activationPackage .#homeConfigurations.ci-omarchy.activationPackage
    for c in ci-mac-desktop ci-mac-server; do nix eval --raw ".#darwinConfigurations.$c.system.drvPath" >/dev/null; done
    ;;
esac
echo "check: ok"
