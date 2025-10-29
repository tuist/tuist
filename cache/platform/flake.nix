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
      "cas-cache-eu-central"
      "cas-cache-us-east"
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
