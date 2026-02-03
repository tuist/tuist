{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/master";
  inputs.disko.url = "github:nix-community/disko";
  inputs.disko.inputs.nixpkgs.follows = "nixpkgs";
  inputs.opnix.url = "github:brizzbuzz/opnix";
  inputs.opnix.inputs.nixpkgs.follows = "nixpkgs";

  outputs = {
    nixpkgs,
    disko,
    opnix,
    ...
  }: let
    hetznerMachines = [
      "cache-eu-central"
      "cache-us-east"
      "cache-us-west"
      "cache-ap-southeast"
      "cache-eu-central-staging"
      "cache-us-east-staging"
      "cache-eu-central-canary"
    ];

    vultrMachines = [
      "cache-sa-west"
    ];

    sharedModules = [
      disko.nixosModules.disko
      opnix.nixosModules.default
      ./configuration.nix
      ./users.nix
    ];

    mkModules = diskConfig: hostname:
      sharedModules
      ++ [
        diskConfig
        {
          networking.hostName = hostname;
        }
      ];

    mkColmenaNode = diskConfig: hostname: {
      deployment = {
        targetHost = "${hostname}.tuist.dev";
        buildOnTarget = true;
      };
      imports = mkModules diskConfig hostname;
    };

    mkNixosConfig = diskConfig: hostname:
      nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = mkModules diskConfig hostname;
      };
  in {
    nixosConfigurations =
      nixpkgs.lib.genAttrs hetznerMachines (mkNixosConfig ./disk-config-hetzner.nix)
      // nixpkgs.lib.genAttrs vultrMachines (mkNixosConfig ./disk-config-vultr.nix);

    colmena =
      {
        meta = {
          nixpkgs = import nixpkgs {system = "x86_64-linux";};
        };
      }
      // nixpkgs.lib.genAttrs hetznerMachines (mkColmenaNode ./disk-config-hetzner.nix)
      // nixpkgs.lib.genAttrs vultrMachines (mkColmenaNode ./disk-config-vultr.nix);
  };
}
