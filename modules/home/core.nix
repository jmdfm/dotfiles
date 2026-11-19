# Every machine, every role: shell, git, ssh, CLI tools, agent config.
# Keep this OS-neutral; macOS-only bits go in mac.nix.
#
# Two rules decide what Nix installs here (both from machine.nix, which
# bootstrap.sh/rebuild.sh detect on every run):
#   machine.omarchy  Omarchy already ships a tool or config -> leave it to Omarchy.
#   machine.mise     language runtimes come from mise (modules/home/mise.nix).
{ config, lib, pkgs, machine, skills, ... }:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
  # Edit-in-place symlink into this repo (no rebuild needed after edits).
  link = path: config.lib.file.mkOutOfStoreSymlink "${dotfiles}/${path}";
  notOmarchy = !machine.omarchy;
in

{
  home.username = machine.user;
  home.homeDirectory = machine.home;
  home.stateVersion = "25.05";

  # CLI tools. Add a line + ./rebuild.sh to install; delete a line to remove.
  home.packages = with pkgs;
    [
      yazi
      just
      tree
      wget
      # language servers
      (lib.hiPrio rust-analyzer)  # wins over rustup's rust-analyzer proxy
      typescript-language-server
      marksman
      gopls
      # linters / formatters
      golangci-lint
      gofumpt
      ruff
    ]
    # Omarchy ships these (gh via its mise tools, gnupg as a system package).
    ++ lib.optionals notOmarchy [
      ripgrep
      fd
      fzf
      jq
      eza
      bat
      btop
      lazygit
      neovim
      gh
      gnupg
    ]
    # Runtimes: from mise where mise is installed (see mise.nix).
    ++ lib.optionals (!machine.mise) [
      go
      nodejs
      bun
      rustup  # toolchains live in ~/.rustup
      uv
    ];

  # Omarchy sets EDITOR itself (omarchy-launch-editor).
  home.sessionVariables = lib.mkIf notOmarchy { EDITOR = "nvim"; };

  home.sessionPath = [
    "$HOME/.local/bin"
    "$HOME/.cargo/bin"
    "$HOME/.bun/bin"
    "$HOME/go/bin"
  ];

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;      # ghost text from history
    syntaxHighlighting.enable = true;  # commands turn green when valid
    defaultKeymap = "viins";           # vi editing: Esc for normal mode, i to insert
    history = {
      size = 32768;
      save = 32768;
      ignoreDups = true;
      ignoreSpace = true;
      share = true;
    };
    initContent = lib.mkMerge [
      ''
        bindkey '^f' autosuggest-accept

        # vi-mode quality of life
        KEYTIMEOUT=1                              # near-instant Esc into normal mode
        bindkey -v '^?' backward-delete-char      # backspace works past the insert point

        # word jumping: ctrl+arrows (CSI 1;5) and alt+arrows (CSI 1;3)
        bindkey '^[[1;5C' forward-word
        bindkey '^[[1;5D' backward-word
        bindkey '^[[1;3C' forward-word
        bindkey '^[[1;3D' backward-word

        export GPG_TTY=$(tty)

        # bun completions
        [ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"
      ''
      # Last, so machine-local settings win.
      (lib.mkOrder 2000 ''
        # machine-local secrets and overrides - never committed to this repo
        [ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
      '')
    ];
    shellAliases = lib.mkMerge [
      # Every machine. On Omarchy this replaces its g=git (these load after
      # Omarchy's aliases).
      { g = "git status"; }
      # Off Omarchy; omarchy.nix brings Omarchy's own aliases instead.
      (lib.mkIf notOmarchy {
        ".." = "cd ..";
        ls = "eza";
        ll = "eza -la --git";
        tree = "eza --tree";
      })
    ];
  };

  # Omarchy has its own zoxide, starship (and ~/.config/starship.toml); omarchy.nix hooks them into zsh.
  programs.zoxide.enable = notOmarchy;  # `z <dir>` jumps by frecency
  programs.starship = lib.mkIf notOmarchy {
    enable = true;
    settings = {
      add_newline = false;
      format = "$directory$git_branch$git_status$cmd_duration$line_break$character";
      character = {
        success_symbol = "[❯](purple)";
        error_symbol = "[❯](red)";
        vimcmd_symbol = "[❮](green)";
      };
      cmd_duration.format = "[$duration]($style) ";
    };
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # Identity is machine-local: ~/.config/git/local holds [user] name, email and
  # signingkey, plus any includeIf that switches profile (e.g. by remote URL).
  # Nothing personal lands in this public repo.
  programs.git = {
    enable = true;
    ignores = [ ".DS_Store" "**/.claude/settings.local.json" ];
    signing = {
      format = "ssh";
      signByDefault = true;
    };
    settings = {
      alias = {
        co = "checkout";
        br = "branch";
        ci = "commit";
        st = "status";
      };
      init.defaultBranch = "master";
      pull.rebase = true;                   # rebase (instead of merge) on pull
      push.autoSetupRemote = true;          # set upstream on first push
      diff = {
        algorithm = "histogram";            # clearer diffs on moved/edited lines
        colorMoved = "plain";               # highlight moved blocks
        mnemonicPrefix = true;              # i/ w/ c/ instead of a/ b/
      };
      commit.verbose = true;                # diff in the commit message editor
      column.ui = "auto";
      branch.sort = "-committerdate";       # most recent branches first
      tag.sort = "-version:refname";        # version-aware tag order
      rerere = {
        enabled = true;                     # record and reuse conflict resolutions
        autoupdate = true;
      };
      gpg.ssh.allowedSignersFile = "~/.ssh/allowed_signers";
      credential."https://github.com".helper = "!gh auth git-credential";
      credential."https://gist.github.com".helper = "!gh auth git-credential";
    };
    includes = [ { path = "~/.config/git/local"; } ];
  };

  # Every signing identity in ~/.config/git/* (email + signingkey pairs) goes
  # into ~/.ssh/allowed_signers, so `git log --show-signature` verifies them.
  # Rebuilt on every switch; skipped when there is nothing to list.
  home.activation.allowedSigners = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    git=${pkgs.git}/bin/git
    tmp="$(mktemp)"
    for f in "$HOME"/.config/git/*; do
      [ -f "$f" ] || continue
      email="$("$git" config -f "$f" user.email 2>/dev/null || true)"
      key="$("$git" config -f "$f" user.signingkey 2>/dev/null || true)"
      [ -n "$email" ] && [ -n "$key" ] || continue
      key="''${key/#\~/$HOME}"
      if [ -f "$key" ]; then key="$(cat "$key")"; fi
      printf '%s namespaces="git" %s\n' "$email" "$key" >> "$tmp"
    done
    if [ -s "$tmp" ]; then
      run mkdir -p "$HOME/.ssh"
      run install -m 600 "$tmp" "$HOME/.ssh/allowed_signers"
    fi
    rm -f "$tmp"
  '';

  # Generic settings only. Hosts, keys, users and IPs go in the machine-local
  # ~/.ssh/config.local, included first so its entries win.
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    includes = [ "~/.ssh/config.local" ];
    settings."*" = {
      AddKeysToAgent = "yes";
    };
  };

  # Linux (non-Omarchy) gets this repo's nvim; Omarchy keeps its LazyVim.
  home.file.".config/nvim" = lib.mkIf notOmarchy { source = link "home/.config/nvim"; };
  home.file.".config/yazi/yazi.toml".source = link "home/.config/yazi/yazi.toml";

  # Agents: one instructions file for Claude Code and Codex. Per-file links
  # only - these dirs also hold auth, history and state that must never be
  # committed. force: replace a pre-existing link from another tool.
  home.file.".claude/CLAUDE.md" = { source = link "agents/AGENTS.md"; force = true; };
  home.file.".codex/AGENTS.md" = { source = link "agents/AGENTS.md"; force = true; };
  home.file.".claude/statusline.sh".source = link "home/.claude/statusline.sh";

  # Skills from other repos (flake inputs, pinned in flake.lock), linked per
  # skill: these dirs also hold skills installed by other tools.
  #   ~/.claude/skills  Claude Code
  #   ~/.agents/skills  Codex and other Agent Skills hosts
  # typesafe-ai: building with TypeSafe System One models (Jev). Needs
  # TYPESAFE_API_KEY, kept in ~/.zshrc.local.
  home.file.".claude/skills/typesafe-ai".source = skills.typesafe;
  home.file.".agents/skills/typesafe-ai".source = skills.typesafe;

  # settings.json is app-written, so merge just the keys this repo owns
  # instead of linking the file. Every other key is left alone. Never fails the switch.
  home.activation.claudeSettings =
    let
      owned = builtins.toJSON {
        statusLine = { type = "command"; command = "bash ~/.claude/statusline.sh"; };
        crossSessionInbound = "accept";   # deliver messages from my other sessions
        idleCompaction = true;            # the default today; pinned
        attribution = { commit = ""; pr = ""; };  # no Claude trailer on commits/PRs
        feedbackSurveyRate = 0;           # never show the session quality survey
        spinnerTipsEnabled = false;       # no tips while working
      };
    in
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      f="$HOME/.claude/settings.json"
      run mkdir -p "$HOME/.claude"
      [ -s "$f" ] || run sh -c "echo '{}' > \"$f\""
      run sh -c '${pkgs.jq}/bin/jq --argjson owned "$2" ". * \$owned" "$1" > "$1.tmp" && mv "$1.tmp" "$1"' _ "$f" '${owned}' || rm -f "$f.tmp"
    '';
}
