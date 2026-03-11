{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.tuist.runner.vmCacheRelay;
in {
  options.tuist.runner.vmCacheRelay = {
    enable = lib.mkEnableOption "VM guest cache relay";

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "192.168.64.1";
      description = "Host address that NAT guests use to reach the relay (vmnet gateway).";
    };

    listenPort = lib.mkOption {
      type = lib.types.port;
      default = 443;
      description = "Host port exposed to guests for cache traffic.";
    };

    cacheAddress = lib.mkOption {
      type = lib.types.str;
      default = "172.16.16.4";
      description = "Private cache address reachable from the host.";
    };

    cachePort = lib.mkOption {
      type = lib.types.port;
      default = 443;
      description = "Target cache port on the private network.";
    };

    logPath = lib.mkOption {
      type = lib.types.str;
      default = "/var/log/tuist-vm-cache-relay.log";
      description = "launchd log file for the cache relay.";
    };

    label = lib.mkOption {
      type = lib.types.str;
      default = "io.tuist.vm-cache-relay";
      description = "launchd label for the managed cache relay service.";
    };
  };

  config = lib.mkIf cfg.enable {
    launchd.daemons.tuist-vm-cache-relay = {
      serviceConfig = {
        Label = cfg.label;
        KeepAlive = true;
        RunAtLoad = true;
        ProcessType = "Background";
        ProgramArguments = [
          "${pkgs.socat}/bin/socat"
          "TCP-LISTEN:${toString cfg.listenPort},bind=${cfg.listenAddress},reuseaddr,fork"
          "TCP:${cfg.cacheAddress}:${toString cfg.cachePort}"
        ];
        StandardOutPath = cfg.logPath;
        StandardErrorPath = cfg.logPath;
        WorkingDirectory = "/var/empty";
      };
    };
  };
}
