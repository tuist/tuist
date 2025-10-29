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

  boot.loader.grub = {
    device = "nodev";
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
  services.openssh.enable = true;
  security.sudo.wheelNeedsPassword = false;

  networking = {
    firewall = {
      enable = true;
      allowedTCPPorts = [
        22 # SSH
        80 # HTTP
        443 # HTTPS
        4369 # EPMD (Erlang Port Mapper Daemon)
      ];
      allowedTCPPortRanges = [
        {
          from = 9100;
          to = 9155;
        } # Erlang distributed node communication
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
