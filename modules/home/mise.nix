# Machines with mise (machine.mise): runtimes (go, node, bun, rust, uv, pnpm,
# zig) come from mise, configured by home/.config/mise/config.toml. mise
# itself is installed outside Nix (Omarchy ships it; elsewhere its installer).
{ config, ... }:

{
  home.file.".config/mise/config.toml".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/home/.config/mise/config.toml";

  programs.zsh.initContent = ''
    command -v mise >/dev/null && eval "$(mise activate zsh)"
  '';
}
