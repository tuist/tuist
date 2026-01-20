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
      "cache-eu-central"
      "cache-us-east"
      "cache-us-west"
      "cache-ap-southeast"
      "cache-eu-central-staging"
      "cache-us-east-staging"
      "cache-eu-central-canary"
    ];

    sharedModules = [
      disko.nixosModules.disko
      opnix.nixosModules.default
      ./configuration.nix
      ./users.nix
    ];

    mkColmenaNode = hostname: {
      deployment = {
        targetHost = "${hostname}.tuist.dev";
        buildOnTarget = true;
      };
      imports = sharedModules ++ [
        {
          networking.hostName = hostname;
        }
      ];
    };
  in {
    colmena = {
      meta = {
        nixpkgs = import nixpkgs {system = "x86_64-linux";};
      };
    } // nixpkgs.lib.genAttrs machines mkColmenaNode;
  };
}
