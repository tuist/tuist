{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/master";
  # Keep host packages unchanged; this revision provides Alloy 1.15.1.
  inputs.nixpkgs-alloy.url = "github:NixOS/nixpkgs/369d1a328b403285e12dd3aa597786c7e364843a";
  inputs.disko.url = "github:nix-community/disko";
  inputs.disko.inputs.nixpkgs.follows = "nixpkgs";
  inputs.opnix.url = "github:brizzbuzz/opnix";
  inputs.opnix.inputs.nixpkgs.follows = "nixpkgs";

  outputs = {
    nixpkgs,
    nixpkgs-alloy,
    disko,
    opnix,
    ...
  }: let
    hetznerMachines = [
      "cache-eu-central"
      "cache-eu-north"
      "cache-us-east"
      "cache-us-east-2"
      "cache-us-east-3"
      "cache-us-west"
      "cache-ap-southeast"
      "cache-eu-central-staging"
      "cache-us-east-staging"
      "cache-eu-central-canary"
    ];

    sharedModules = [
      disko.nixosModules.disko
      opnix.nixosModules.default
      {
        nixpkgs.overlays = [
          (_final: prev: {
            grafana-alloy = nixpkgs-alloy.legacyPackages.${prev.stdenv.hostPlatform.system}.grafana-alloy;
          })
        ];
      }
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
      nixpkgs.lib.genAttrs hetznerMachines (mkNixosConfig ./disk-config-hetzner.nix);

    colmena =
      {
        meta = {
          nixpkgs = import nixpkgs {system = "x86_64-linux";};
        };
      }
      // nixpkgs.lib.genAttrs hetznerMachines (mkColmenaNode ./disk-config-hetzner.nix);
  };
}
