# Every Mac (desktop and server roles): Homebrew on PATH, data and media
# tools, fonts, Flick.
{ config, lib, pkgs, ... }:

let
  link = path: config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/${path}";
  flick = "${config.home.homeDirectory}/Applications/Flick.app/Contents/MacOS/Flick";
in

{
  home.packages = with pkgs; [
    # data
    postgresql  # psql, pg_dump, pg_restore
    # cloud
    google-cloud-sdk
    _1password-cli  # `op`
    # media
    ffmpeg
    mpv  # terminal video: yazi opens videos with mpv --vo=tct
    # learning
    rustlings
    # font
    nerd-fonts.blex-mono
  ];
  fonts.fontconfig.enable = true;

  home.sessionPath = [
    "/Applications/Visual Studio Code.app/Contents/Resources/app/bin"
  ];

  programs.zsh.profileExtra = ''
    eval "$(/opt/homebrew/bin/brew shellenv zsh)"
  '';
  # Installed brew packages/casks/taps missing from the Nix lists.
  programs.zsh.shellAliases.brew-drift = "$HOME/.dotfiles/brew-drift.sh";
  # No sleep, lid closed too, while it runs (like caffeinate).
  programs.zsh.shellAliases.sleep-off = "$HOME/.dotfiles/sleep-off.sh";

  # macOS keychain for ssh key passphrases; OrbStack's ssh hosts if installed
  # (a missing Include file is skipped).
  programs.ssh.includes = [ "~/.orbstack/ssh/config" ];
  programs.ssh.settings."*".UseKeychain = "yes";

  # Target dir for system.defaults.screencapture.location.
  home.file."Pictures/Screenshots/.keep".text = "";

  # Flick launcher (github.com/jayminwest/flick, installed by its
  # `scripts/bundle.sh --install`). Shared config here; a Mac's own tables go
  # in a machine-local config.<LocalHostName lowercase>.toml beside it.
  home.file.".config/flick/config.toml".source = link "home/.config/flick/config.toml";
  # Restarts on crash; "Quit Flick" stays quit; not installed yet = clean exit.
  launchd.agents.flick = {
    enable = true;
    config = {
      ProgramArguments = [ "/bin/sh" "-c" ''[ -x "$0" ] || exit 0; exec "$0"'' flick ];
      RunAtLoad = true;
      KeepAlive.SuccessfulExit = false;
      ProcessType = "Interactive";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/flick.log";
    };
  };
}
