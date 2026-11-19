# CI example. On a real machine rebuild.sh writes ~/.config/dotfiles/machine.nix
# and passes that directory in place of this one.
{
  role = "server";
  user = "user";
  system = "x86_64-linux";
  omarchy = false;
  mise = false;
}
