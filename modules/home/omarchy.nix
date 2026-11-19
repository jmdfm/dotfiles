# Omarchy machines (machine.omarchy): zsh on top of Omarchy's own shell setup.
#
# Omarchy's shell defaults (/usr/share/omarchy/default/bash) are written for
# bash. The POSIX parts (envs, env-bootstrap) are sourced as-is; aliases and
# functions are sourced under ksh emulation, which covers the bash syntax they
# use ([[ ]], (( )), local). init and inputrc are bash-only and are redone
# here for zsh. Tools come from Omarchy (starship, zoxide, fzf); mise is
# hooked in by mise.nix.
{ lib, ... }:

{
  programs.zsh = {
    # Every zsh, including non-interactive ones (scripts, ssh commands):
    # OMARCHY_PATH, PATH (mise wrappers + shims), EDITOR, BROWSER, MANPAGER, locale.
    envExtra = ''
      : "''${OMARCHY_PATH:=/usr/share/omarchy}"
      [ -r "$OMARCHY_PATH/default/bash/envs" ] && emulate sh -c 'source "$OMARCHY_PATH/default/bash/envs"'
    '';

    initContent = lib.mkOrder 900 ''
      # Omarchy's aliases (ls/lt/ff/eff, cd -> zoxide, g/gcm/n/...) and
      # functions (compression, drives, worktrees, ...). Functions defined under
      # ksh emulation keep it when they run.
      if [ -d "$OMARCHY_PATH/default/bash" ]; then
        emulate ksh -c 'source "$OMARCHY_PATH/default/bash/aliases"'
        for _f in "$OMARCHY_PATH"/default/bash/fns/*(N); do
          emulate ksh -c 'source "$_f"'
        done
        unset _f
      fi

      # Omarchy's init, for zsh.
      if [[ $TERM != dumb ]] && command -v starship >/dev/null; then
        eval "$(starship init zsh)"
      fi
      command -v zoxide >/dev/null && eval "$(zoxide init zsh)"
      # Key bindings only (Ctrl-R, Ctrl-T, Alt-C), as Omarchy does for bash.
      [ -r /usr/share/fzf/key-bindings.zsh ] && source /usr/share/fzf/key-bindings.zsh

      # Omarchy's inputrc, for zsh: case-insensitive completion.
      zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
    '';
  };
}
