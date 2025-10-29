{
  modulesPath,
  lib,
  pkgs,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
    ./disk-config.nix
    ./nginx.nix
  ];
  system.stateVersion = "25.11";

  boot = {
    loader.grub = {
      device = "nodev";
      efiSupport = true;
      efiInstallAsRemovable = true;
    };
    kernelPackages = pkgs.linuxPackages_latest;
  };

  services.openssh.enable = true;
  security.sudo.wheelNeedsPassword = false;

  networking = {
    firewall = {
      enable = true;
      allowedTCPPorts = [
        22
        80
        443
        4369
      ];
      allowedTCPPortRanges = [
        {
          from = 9100;
          to = 9155;
        }
      ];
    };
  };

  virtualisation.docker = {
    enable = true;
    logDriver = "json-file";
  };

  # services.tailscale = {
  #   enable = true;
  #   openFirewall = true;
  #   useRoutingFeatures = "server";
  # };

  environment.systemPackages = map lib.lowPrio [
    pkgs.curl
    pkgs.gitMinimal
  ];
}
