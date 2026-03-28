{ config, pkgs, ... }:

let
  deployDir = "/Users/xcode-processor/xcode_processor";
  currentRelease = "${deployDir}/current";

  envScript = pkgs.writeScript "xcode-processor-env" ''
    #!/bin/bash
    export PORT="4003"
    export MIX_ENV="prod"
    export RELEASE_NAME="xcode_processor"
    export PHX_HOST="xcode-processor-paris-1.tuist.dev"
    export SECRET_KEY_BASE="$(cat ${config.sops.secrets.secret_key_base.path})"
    export WEBHOOK_SECRET="$(cat ${config.sops.secrets.webhook_secret.path})"
    export S3_ENDPOINT="$(cat ${config.sops.secrets.s3_endpoint.path})"
    export S3_BUCKET="$(cat ${config.sops.secrets.s3_bucket.path})"
    export S3_ACCESS_KEY_ID="$(cat ${config.sops.secrets.s3_access_key_id.path})"
    export S3_SECRET_ACCESS_KEY="$(cat ${config.sops.secrets.s3_secret_access_key.path})"
    export LOKI_URL="http://127.0.0.1:3100"
    export OTEL_EXPORTER_OTLP_ENDPOINT="http://127.0.0.1:4317"
    export GIT_SHA="$(cat ${currentRelease}/.git_sha 2>/dev/null || echo unknown)"
    exec ${currentRelease}/bin/xcode_processor start
  '';
in
{
  services.openssh.enable = true;

  security.pam.services.sudo_local.touchIdAuth = true;

  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    htop
    caddy
  ];

  launchd.daemons."dev.tuist.caddy" = {
    serviceConfig = {
      ProgramArguments = [
        "${pkgs.caddy}/bin/caddy"
        "run"
        "--config"
        "/etc/caddy/Caddyfile"
      ];
      KeepAlive = true;
      RunAtLoad = true;
      StandardOutPath = "/var/log/caddy/stdout.log";
      StandardErrorPath = "/var/log/caddy/stderr.log";
      EnvironmentVariables = {
        HOME = "/var/lib/caddy";
        XDG_DATA_HOME = "/var/lib/caddy/data";
        XDG_CONFIG_HOME = "/var/lib/caddy/config";
      };
    };
  };

  launchd.daemons."dev.tuist.xcode-processor" = {
    serviceConfig = {
      ProgramArguments = [ "${envScript}" ];
      KeepAlive = true;
      RunAtLoad = true;
      StandardOutPath = "/var/log/xcode-processor/stdout.log";
      StandardErrorPath = "/var/log/xcode-processor/stderr.log";
      WorkingDirectory = deployDir;
    };
  };

  users.users.xcode-processor = {
    home = "/Users/xcode-processor";
    shell = pkgs.zsh;
    isHidden = true;
  };

  users.users.github-actions = {
    home = "/Users/github-actions";
    shell = pkgs.bash;
    openssh.authorizedKeys.keys = [
      # Populated via GitHub environment secrets
    ];
  };

  system.stateVersion = 6;
}
