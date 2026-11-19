{
  description = "Cross-platform dotfiles: nix-darwin + home-manager on macOS, home-manager on Linux";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    # Linux: same release, the channel Hydra builds (and caches) for Linux.
    nixpkgs-linux.url = "github:NixOS/nixpkgs/nixos-26.05";
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    # Standalone home-manager on Linux builds against the Linux channel.
    home-manager-linux.url = "github:nix-community/home-manager/release-26.05";
    home-manager-linux.inputs.nixpkgs.follows = "nixpkgs-linux";

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    # Agent skills from their own repos, pinned in flake.lock.
    # Update: nix flake update typesafe-skills
    typesafe-skills = { url = "github:typesafe-ai/skills"; flake = false; };

    # This machine: ~/.config/dotfiles/machine.nix, written by bootstrap.sh and
    # passed in by rebuild.sh (--override-input). The stub is the CI example.
    machine = { url = "path:./stub/machine"; flake = false; };
  };

  outputs = { self, nixpkgs, nixpkgs-linux, nix-darwin, home-manager, home-manager-linux, nix-homebrew, machine, typesafe-skills }:
    let
      lib = nixpkgs.lib;
      # Skill sources handed to home modules (core.nix links them into each agent).
      skills = { typesafe = "${typesafe-skills}/skills/typesafe-ai"; };
      isDarwinSystem = lib.hasSuffix "darwin";

      # What each role adds on top of modules/home/core.nix (every machine).
      # Linux has no desktop-specific Nix modules: on Omarchy the desktop is
      # Omarchy's, and its extra packages come from omarchy/packages.txt.
      roles = {
        darwin = {
          desktop = { darwin = [ ./modules/darwin.nix ./modules/darwin-desktop.nix ]; home = [ ./modules/home/mac.nix ./modules/home/mac-desktop.nix ]; };
          server = { darwin = [ ./modules/darwin.nix ]; home = [ ./modules/home/mac.nix ]; };
        };
        linux = {
          desktop = { home = [ ./modules/home/linux.nix ]; };
          server = { home = [ ./modules/home/linux.nix ]; };
        };
      };

      # machine: { role, user, system, home?, omarchy?, mise? }
      norm = m: {
        home = (if isDarwinSystem m.system then "/Users/" else "/home/") + m.user;
        omarchy = false;
        mise = false;
      } // m;

      # Home modules for a machine: core + role + what was detected on it.
      homeModules = m: os:
        [ ./modules/home/core.nix ]
        ++ roles.${os}.${m.role}.home
        ++ lib.optional m.omarchy ./modules/home/omarchy.nix
        ++ lib.optional m.mise ./modules/home/mise.nix;

      mkDarwin = m0:
        let m = norm m0; in
        nix-darwin.lib.darwinSystem {
          specialArgs = { machine = m; };
          modules = roles.darwin.${m.role}.darwin ++ [
            { nixpkgs.hostPlatform = m.system; }
            nix-homebrew.darwinModules.nix-homebrew
            home-manager.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              # A real file where home-manager wants a link is moved aside, not fatal.
              home-manager.backupFileExtension = "hm-backup";
              home-manager.extraSpecialArgs = { machine = m; inherit skills; };
              home-manager.users.${m.user}.imports = homeModules m "darwin";
            }
          ];
        };

      mkHome = m0:
        let m = norm m0; in
        home-manager-linux.lib.homeManagerConfiguration {
          pkgs = import nixpkgs-linux { system = m.system; config.allowUnfree = true; };
          extraSpecialArgs = { machine = m; inherit skills; };
          modules = homeModules m "linux";
        };

      this = import "${machine}/machine.nix";
      example = role: system: extra: { inherit role system; user = "user"; } // extra;
    in
    {
      # `default` is this machine; ci-* build every role in check.sh and CI.
      darwinConfigurations = {
        ci-mac-desktop = mkDarwin (example "desktop" "aarch64-darwin" { });
        ci-mac-server = mkDarwin (example "server" "aarch64-darwin" { mise = true; });
      } // lib.optionalAttrs (isDarwinSystem this.system) { default = mkDarwin this; };

      homeConfigurations = {
        ci-linux = mkHome (example "server" "x86_64-linux" { });
        ci-omarchy = mkHome (example "desktop" "x86_64-linux" { omarchy = true; mise = true; });
      } // lib.optionalAttrs (!isDarwinSystem this.system) { default = mkHome this; };

      packages = lib.genAttrs [ "aarch64-darwin" "x86_64-darwin" ] (system: {
        # rebuild.sh runs this pinned darwin-rebuild, so a fresh Mac needs nothing else.
        darwin-rebuild = nix-darwin.packages.${system}.darwin-rebuild;
      });
    };
}
