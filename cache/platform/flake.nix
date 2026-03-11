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
    machines = {
      "cache-eu-central" = {
        diskConfig = ./disk-config-hetzner.nix;
        targetHost = "cache-eu-central.tuist.dev";
        domain = "tuist.dev";
      };
      "cache-eu-north" = {
        diskConfig = ./disk-config-hetzner.nix;
        targetHost = "cache-eu-north.tuist.dev";
        domain = "tuist.dev";
      };
      "cache-us-east" = {
        diskConfig = ./disk-config-hetzner.nix;
        targetHost = "cache-us-east.tuist.dev";
        domain = "tuist.dev";
      };
      "cache-us-west" = {
        diskConfig = ./disk-config-hetzner.nix;
        targetHost = "cache-us-west.tuist.dev";
        domain = "tuist.dev";
      };
      "cache-ap-southeast" = {
        diskConfig = ./disk-config-hetzner.nix;
        targetHost = "cache-ap-southeast.tuist.dev";
        domain = "tuist.dev";
      };
      "cache-eu-central-staging" = {
        diskConfig = ./disk-config-hetzner.nix;
        targetHost = "cache-eu-central-staging.tuist.dev";
        domain = "tuist.dev";
      };
      "cache-us-east-staging" = {
        diskConfig = ./disk-config-hetzner.nix;
        targetHost = "cache-us-east-staging.tuist.dev";
        domain = "tuist.dev";
      };
      "cache-eu-central-canary" = {
        diskConfig = ./disk-config-hetzner.nix;
        targetHost = "cache-eu-central-canary.tuist.dev";
        domain = "tuist.dev";
      };
      "cache-sa-west" = {
        diskConfig = ./disk-config-vultr.nix;
        targetHost = "cache-sa-west.tuist.dev";
        domain = "tuist.dev";
      };
      "tuist-01-test-cache" = {
        diskConfig = ./disk-config-scaleway.nix;
        targetHost = "51.159.83.73";
        domain = "par.runners.tuist.dev";
        privateIPv4Routes = [
          {
            interface = "ens6";
            address = "172.16.16.0";
            prefixLength = 22;
          }
        ];
      };
    };

    sharedModules = [
      disko.nixosModules.disko
      opnix.nixosModules.default
      ./configuration.nix
      ./users.nix
    ];

    mkModules = machine: hostname:
      sharedModules
      ++ [
        machine.diskConfig
        {
          networking.hostName = hostname;
          networking.domain = machine.domain;
        }
      ]
      ++ nixpkgs.lib.optional (machine ? privateIPv4Routes) {
        networking.interfaces = nixpkgs.lib.mapAttrs (_: routes: {
          ipv4.routes = map (route: {
            inherit (route) address prefixLength;
            options.scope = "link";
          }) routes;
        }) (nixpkgs.lib.groupBy (route: route.interface) machine.privateIPv4Routes);
      };

    mkColmenaNode = hostname: machine: {
      deployment = {
        targetHost = machine.targetHost;
        buildOnTarget = true;
      };
      imports = mkModules machine hostname;
    };

    mkNixosConfig = machine: hostname:
      nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = mkModules machine hostname;
      };
  in {
    nixosConfigurations = nixpkgs.lib.mapAttrs (
      hostname: machine: mkNixosConfig machine hostname
    ) machines;

    colmena =
      {
        meta = {
          nixpkgs = import nixpkgs {system = "x86_64-linux";};
        };
      }
      // nixpkgs.lib.mapAttrs mkColmenaNode machines;
  };
}
