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
    machines = [
      "processor-staging"
      "processor-canary"
      "processor"
    ];

    sharedModules = [
      disko.nixosModules.disko
      opnix.nixosModules.default
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

    mkColmenaNode = hostname: {
      deployment = {
        targetHost = "${hostname}.tuist.dev";
        # Defer SSH user to the operator's ~/.ssh/config so the flake stays
        # pure (no --impure / env vars). Privilege escalation via passwordless
        # sudo for wheel users.
        targetUser = null;
        privilegeEscalationCommand = ["sudo" "-H" "--"];
        buildOnTarget = true;
      };
      imports = mkModules hostname;
    };

    mkNixosConfig = hostname:
      nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = mkModules hostname;
      };
  in {
    nixosConfigurations =
      nixpkgs.lib.genAttrs machines mkNixosConfig;

    colmena =
      {
        meta = {
          nixpkgs = import nixpkgs {system = "x86_64-linux";};
        };
      }
      // nixpkgs.lib.genAttrs machines mkColmenaNode;
  };
}
