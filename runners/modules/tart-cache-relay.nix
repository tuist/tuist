{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.tuist.runner.tartCacheRelay;
in {
  options.tuist.runner.tartCacheRelay = {
    enable = lib.mkEnableOption "Tart guest cache relay";

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "192.168.64.1";
      description = "Host address that Tart NAT guests use to reach the relay.";
    };

    listenPort = lib.mkOption {
      type = lib.types.port;
      default = 443;
      description = "Host port exposed to Tart guests for cache traffic.";
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
      default = "/var/log/tuist-tart-cache-relay.log";
      description = "launchd log file for the cache relay.";
    };

    label = lib.mkOption {
      type = lib.types.str;
      default = "io.tuist.tart-cache-relay";
      description = "launchd label for the managed cache relay service.";
    };
  };

  config = lib.mkIf cfg.enable {
    launchd.daemons.tuist-tart-cache-relay = {
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
