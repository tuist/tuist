{
  description = "Tuist macOS GitHub runners";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };

    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
  };

  outputs = inputs @ {
    nix-darwin,
    nix-homebrew,
    ...
  }: let
    system = "aarch64-darwin";
    mkDarwin = hostModule:
      nix-darwin.lib.darwinSystem {
        inherit system;
        specialArgs = {
          inherit inputs;
        };
        modules = [
          nix-homebrew.darwinModules.nix-homebrew
          ./modules/base.nix
          ./modules/homebrew.nix
          inputs.sops-nix.darwinModules.sops
          ./modules/secrets.nix
          ./modules/vm-cache-relay.nix
          ./modules/github-runner.nix
          hostModule
        ];
      };
  in {
    darwinConfigurations."scaleway-m1-01" = mkDarwin ./hosts/scaleway-m1-01/default.nix;
  };
}
