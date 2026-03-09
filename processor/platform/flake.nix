{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/master";
  inputs.disko.url = "github:nix-community/disko";
  inputs.disko.inputs.nixpkgs.follows = "nixpkgs";

  outputs = {
    nixpkgs,
    disko,
    ...
  }: let
    machines = [
      "processor-staging"
    ];

    sharedModules = [
      disko.nixosModules.disko
      ./configuration.nix
      ./users.nix
    ];

    mkModules = hostname:
      sharedModules
      ++ [
        ./disk-config-hetzner.nix
        {
          networking.hostName = hostname;
        }
      ];

    mkNixosConfig = hostname:
      nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = mkModules hostname;
      };
  in {
    nixosConfigurations =
      nixpkgs.lib.genAttrs machines mkNixosConfig;
  };
}
