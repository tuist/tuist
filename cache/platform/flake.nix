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
      "cache-eu-central"
      "cache-us-east"
      "cache-eu-central-staging"
      "cache-us-east-staging"
      "cache-eu-central-canary"
    ];

    mkMachine = hostname: {
      name = hostname;
      value = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          disko.nixosModules.disko
          ./configuration.nix
          ./users.nix
          {
            networking.hostName = hostname;
          }
        ];
      };
    };
  in {
    nixosConfigurations = builtins.listToAttrs (map mkMachine machines);
  };
}
