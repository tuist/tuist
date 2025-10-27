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
  ];
  system.stateVersion = "25.11";

  boot.loader.grub = {
    device = "nodev";
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
  services.openssh.enable = true;
  security.sudo.wheelNeedsPassword = false;

  networking = {
    hostName = "cas-cache-us-east";
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
