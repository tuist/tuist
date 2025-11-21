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
    ./secrets.nix
    ./alloy.nix
  ];
  system.stateVersion = "25.11";

  boot = {
    loader.grub = {
      device = "nodev";
      efiSupport = true;
      efiInstallAsRemovable = true;
    };
    kernelPackages = pkgs.linuxPackages_6_17;
    kernel.sysctl = {
      "net.core.somaxconn" = 4096;
      "net.ipv4.tcp_max_syn_backlog" = 4096;
      "net.core.rmem_max" = 134217728;
      "net.core.wmem_max" = 134217728;
      "net.ipv4.tcp_rmem" = "4096 87380 67108864";
      "net.ipv4.tcp_wmem" = "4096 65536 67108864";
    };
  };

  services.openssh.enable = true;
  security.sudo.wheelNeedsPassword = false;

  security.pam.loginLimits = [
    {
      domain = "*";
      type = "soft";
      item = "nofile";
      value = "65535";
    }
    {
      domain = "*";
      type = "hard";
      item = "nofile";
      value = "65535";
    }
  ];

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

  environment.systemPackages = map lib.lowPrio [
    pkgs.curl
    pkgs.gitMinimal
    pkgs.parted
    pkgs.gptfdisk
    pkgs.sqlite
  ];

  systemd.tmpfiles.rules = [
    "Z /cas 0755 cache cache - -"
    "d /var/lib/cache 0755 cache cache - -"
    "d /run/cache 0777 root root - -"
  ];
}
