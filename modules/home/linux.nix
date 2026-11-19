# Every Linux machine (Omarchy or any other distro): standalone home-manager
# on a non-NixOS system.
{ config, pkgs, ... }:

{
  targets.genericLinux.enable = true;
  # `home-manager` on PATH (news, generations); rebuild.sh doesn't need it.
  programs.home-manager.enable = true;

  # Terminfo for terminals the distro may lack (ssh in from Ghostty sends
  # TERM=xterm-ghostty; without it zsh's line editor garbles input).
  # genericLinux only sets TERMINFO_DIRS for the desktop session; this covers
  # every shell, ssh included, before home-manager re-exports TERM.
  home.packages = [ pkgs.ghostty.terminfo ];
  home.sessionVariables.TERMINFO_DIRS =
    "${config.home.profileDirectory}/share/terminfo\${TERMINFO_DIRS:+:$TERMINFO_DIRS}:/etc/terminfo:/usr/share/terminfo";

  # Shells started outside the desktop session (ssh logins, agents, tmux) don't
  # get SSH_AUTH_SOCK. Point every zsh, non-interactive included, at the
  # agent the desktop uses: Omarchy's gcr-ssh-agent (Menu > Setup > Security >
  # SSH Agent) if enabled, else systemd's ssh-agent.socket.
  programs.zsh.envExtra = ''
    if [ -z "$SSH_AUTH_SOCK" ]; then
      _rt="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
      for _s in "$_rt/gcr/ssh" "$_rt/ssh-agent.socket"; do
        if [ -S "$_s" ]; then export SSH_AUTH_SOCK="$_s"; break; fi
      done
      unset _rt _s
    fi
  '';
}
