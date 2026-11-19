# dotfiles

One Nix flake for every machine: macOS (nix-darwin + home-manager) and Linux
(home-manager). Same zsh, git, ssh and CLI tools everywhere.

- **Omarchy installed:** Omarchy keeps its desktop, nvim, prompt and core tools;
  zsh loads Omarchy's env, aliases and functions.
- **mise installed:** language runtimes come from mise; Nix installs them only
  where mise is absent.

## Quickstart

```sh
git clone https://github.com/<you>/dotfiles ~/.dotfiles
~/.dotfiles/bootstrap.sh --role desktop   # or: server (headless, CLI only)
```

Run it in a real terminal: it asks for sudo (Nix, zsh, `chsh`, Omarchy
packages). Then log in again and:

1. Fill in the machine-local files below (at least `~/.config/git/local`).
2. Add each SSH signing key to its GitHub account as a **Signing key**
   (Settings → SSH and GPG keys → New SSH key → Key type).
3. `gh auth login`, and `mise install` if you use mise.

After any change or `git pull`:

```sh
cd ~/.dotfiles && ./rebuild.sh
```

| Command | Does |
|---|---|
| `./bootstrap.sh --role desktop\|server` | Fresh machine. Safe to re-run. |
| `./rebuild.sh` | Detect Omarchy/mise, build, activate. |
| `./check.sh` | Public-safety scan + build every role (run before pushing). |

## Private items

This repo is public. Anything that identifies you, a machine, a network or a
key lives in machine-local files that are never committed. `bootstrap.sh`
creates commented starters for the ones marked ★ if they are missing.

| File | Holds |
|---|---|
| `~/.config/git/local` ★ | `[user]` name, email, `signingkey`; `includeIf` rules for other profiles |
| `~/.config/git/<profile>` | A second identity (e.g. work), included by remote URL |
| `~/.ssh/config.local` ★ | SSH hosts, aliases, users, `IdentityFile` lines (included first) |
| `~/.zshrc.local` ★ | Secrets and env vars, e.g. `TYPESAFE_API_KEY` (sourced last) |
| `~/.config/dotfiles/deny.txt` ★ | Extra patterns `check.sh` refuses to commit (names, domains, hostnames) |
| `~/.config/dotfiles/machine.nix` | Role, user, OS, Omarchy/mise detection. Written by `rebuild.sh` |
| `~/.ssh/allowed_signers` | Built on every rebuild from each email + `signingkey` in `~/.config/git/*` |

### Two git identities

Commits are SSH-signed everywhere. To sign work repos with a work key, clone
them through an SSH alias and switch profile on the remote URL.

In `~/.ssh/config.local`, add a host block named `work-github` with
`HostName github.com`, `User git`, `IdentityFile ~/.ssh/id_ed25519_work` and
`IdentitiesOnly yes`. Then:

```ini
# ~/.config/git/local
[user]
  name = Your Name
  email = you@example.com
  signingkey = ~/.ssh/id_ed25519_personal.pub
[includeIf "hasconfig:remote.*.url:work-github:*/**"]
  path = ~/.config/git/work

# ~/.config/git/work
[user]
  email = work@example.com
  signingkey = ~/.ssh/id_ed25519_work.pub
```

Clone with `git clone work-github:org/repo`. Use `*/**`, not `**`: git's `**`
only crosses `/` after a slash.

Signing reads keys from ssh-agent. A passphrase-protected key is added
automatically the first time you use it over SSH (`git fetch`), or by hand with
`ssh-add`.

### Guard rails

- `check.sh` runs on every commit (hooks) and in CI. It blocks emails (except
  GitHub noreply and `example.com`), private and Tailscale IPs, SSH host
  blocks, private keys, home paths, and anything in your `deny.txt`.
- `.gitignore` and `check.sh` refuse key files and `*.local` files outright.
- `rebuild.sh` sets this repo's commit email to a GitHub noreply address.

See [AGENTS.md](AGENTS.md) for layout and where each kind of change goes.

Based on Jaymin West's dotfiles: https://github.com/jayminwest/dotfiles
