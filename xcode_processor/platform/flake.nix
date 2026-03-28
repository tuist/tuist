{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nix-darwin, sops-nix, ... }:
    let
      system = "aarch64-darwin";
      sharedModules = [
        sops-nix.darwinModules.sops
        ./configuration.nix
        ./users.nix
        ./secrets.nix
        ./packages.nix
        ./alloy.nix
      ];
    in
    {
      darwinConfigurations = {
        "xcode-processor-production" = nix-darwin.lib.darwinSystem {
          inherit system;
          modules = sharedModules ++ [
            ./hosts/xcode-processor-production.nix
          ];
        };
        "xcode-processor-canary" = nix-darwin.lib.darwinSystem {
          inherit system;
          modules = sharedModules ++ [
            ./hosts/xcode-processor-canary.nix
          ];
        };
      };
    };
}
