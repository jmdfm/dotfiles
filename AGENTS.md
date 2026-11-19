# AGENTS.md — dotfiles

One public repo configures every machine: macOS (nix-darwin + home-manager)
and Linux (standalone home-manager), Omarchy or any other distro.

## Rule zero: this repo is public

Nothing that identifies a person, machine, network or key: no emails (except
GitHub noreply and `example.com`), hostnames, IPs, ssh hosts/users/keys, tailnet
names, `/Users/<name>` or `/home/<name>` paths, employer names. This applies to
files, commit messages and comments. Use placeholders (`server.example.com`,
`work-github`, `me@server`, `$HOME`). `./check.sh` enforces this in the commit
hooks and CI. Never weaken a pattern in it; add private ones to the
machine-local `~/.config/dotfiles/deny.txt`.

## Commands

| Command | Does |
|---|---|
| `./bootstrap.sh --role desktop\|server` | Fresh machine: installs Nix, links `~/.dotfiles`, makes zsh the login shell, creates the machine-local starter files, runs `rebuild.sh`. Safe to re-run. |
| `./rebuild.sh [--role ...]` | Detects Omarchy/mise, writes `~/.config/dotfiles/machine.nix`, installs `omarchy/packages.txt` on Omarchy, builds + activates. After every change or `git pull`. |
| `./check.sh` | Public-safety scan + build every role. Must pass before pushing. |
| `./check.sh --fast` | Scan only (pre-commit hook). |
| `./brew-drift.sh` | macOS: brew packages installed but not declared. Read-only. |

The repo lives at `~/.dotfiles` on every machine. All config links resolve
through that path.

## Machines

`machine.nix` is `{ role, user, home, system, omarchy, mise }`. Only
`rebuild.sh` writes it, never committed; `stub/machine` is the CI example.

| Role | macOS | Linux |
|---|---|---|
| `desktop` | `darwin.nix` `darwin-desktop.nix` + home `mac` `mac-desktop` | home `linux` (+ `omarchy/packages.txt` on Omarchy) |
| `server` | `darwin.nix` + home `mac` | home `linux` |

Every machine also gets home `core`. Detected on each rebuild:

- **omarchy** (`/usr/share/omarchy` exists): adds `home/omarchy.nix`. Nix
  skips tools and configs Omarchy ships (ripgrep, fd, fzf, jq, eza, bat, btop,
  lazygit, neovim + LazyVim, gh, gnupg, starship, zoxide, EDITOR) and zsh
  loads Omarchy's env, aliases and functions.
- **mise** (on PATH): adds `home/mise.nix`. Runtimes (go, node, bun, rust, uv,
  pnpm, zig) come from mise via `home/.config/mise/config.toml`; Nix installs
  them only where mise is absent.

## Layout

```
flake.nix                   roles, mkDarwin/mkHome, ci-* configs
modules/darwin.nix          every Mac: macOS defaults, Homebrew base lists
modules/darwin-desktop.nix  Mac desktop casks/brews, AeroSpace install
modules/home/core.nix       EVERY machine: packages, zsh, git, ssh, agents
modules/home/omarchy.nix    Omarchy: zsh on Omarchy's shell defaults
modules/home/mise.nix       mise: config link + zsh hook
modules/home/mac.nix        every Mac: data/media tools, fonts, Flick, ssh keychain
modules/home/mac-desktop.nix  Mac desktop: AeroSpace config
modules/home/linux.nix      every Linux: genericLinux
omarchy/packages.txt        pacman packages for Omarchy machines
omarchy/services.txt        systemd services rebuild.sh enables on Omarchy
pkgs/                       AeroSpace (pinned release binary)
home/                       real config files, linked edit-in-place into ~
agents/AGENTS.md            global agent instructions (~/.claude/CLAUDE.md, ~/.codex/AGENTS.md)
stub/                       default flake input (CI machine)
```

## Where a change goes

- **A CLI tool for every machine**: `modules/home/core.nix` `home.packages`,
  in the right list (always / not on Omarchy / not with mise).
- **A runtime**: `home/.config/mise/config.toml` (or `mise use -g`), and the
  no-mise list in `core.nix`.
- **A GUI app**: Mac → a cask in `darwin-desktop.nix`; Omarchy → a line in
  `omarchy/packages.txt` (plus `omarchy/services.txt` if it needs a
  service). Non-Omarchy Linux is CLI only.
- **Config for an app** (yazi, nvim, aerospace, flick, mise): edit
  `home/.config/<app>/...`. Linked out-of-store, so edits apply without a
  rebuild. A new file needs a `home.file` link in the right module.
- **A Homebrew formula/cask**: `darwin.nix` for every Mac,
  `darwin-desktop.nix` for desktops only. Prefer nixpkgs.
- **Claude Code settings**: the `owned` keys in `core.nix`
  (`claudeSettings`); only those keys are merged into `~/.claude/settings.json`.
- **Anything personal**: a machine-local file (below), never this repo.

## Machine-local files (never committed)

`bootstrap.sh` creates commented starters if missing.

| File | Holds |
|---|---|
| `~/.config/git/local` | `[user]` name/email/signingkey; `includeIf` for other profiles |
| `~/.config/git/<profile>` | a second identity, included by remote URL |
| `~/.ssh/config.local` | ssh hosts, aliases, users, IdentityFile |
| `~/.zshrc.local` | secrets, env |
| `~/.config/dotfiles/deny.txt` | extra `check.sh` patterns |
| `~/.config/flick/config.<host>.toml` | Mac: Flick endpoints |

Commits are SSH-signed everywhere. `~/.ssh/allowed_signers` is rebuilt from
every email + signingkey pair in `~/.config/git/*` on each rebuild.

## Verify

- `./check.sh` before every push. On Linux it builds both Linux configs and
  evaluates the darwin ones; CI does the same.
- `./rebuild.sh` to see a change on this machine.
- Out-of-store links mean a broken file in `home/` breaks the app, not the
  build. Open the app to check.

## Manual steps (cannot be automated)

- **Any machine:** fill in `~/.config/git/local`, add each signing key to its
  GitHub account as a *Signing key*, `gh auth login`, agent logins.
- **Mac desktop:** install the Rex terminal by hand (no cask yet). Grant
  AeroSpace Accessibility on first launch. Install Flick
  from github.com/jayminwest/flick (`scripts/bundle.sh --install`). Download the
  whisper model for dictation (see `home/.config/flick/config.toml`).
