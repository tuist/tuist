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
    export S3_REGION="$(cat ${config.sops.secrets.s3_region.path})"
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

  # Directories created on activation
  system.activationScripts.postActivation.text = ''
    mkdir -p /var/log/xcode-processor
    mkdir -p /var/log/caddy
    mkdir -p /var/lib/caddy
    mkdir -p /var/log/grafana-alloy
    mkdir -p ${deployDir}/releases
    chown -R github-actions:staff ${deployDir}

    # Ensure github-actions has a home directory and SSH access
    createhomedir -c -u github-actions 2>/dev/null || mkdir -p /Users/github-actions
    chown github-actions:staff /Users/github-actions
    chmod 755 /Users/github-actions

    # Add github-actions to SSH access group if it exists
    if dseditgroup -o read com.apple.access_ssh &>/dev/null; then
      dseditgroup -o edit -a github-actions -t user com.apple.access_ssh 2>/dev/null || true
    fi
  '';

  # Sudoers for deploy user to restart the service
  environment.etc."sudoers.d/xcode-processor-deploy" = {
    text = ''
      github-actions ALL=(ALL) NOPASSWD: /bin/launchctl bootout system/dev.tuist.xcode-processor
      github-actions ALL=(ALL) NOPASSWD: /bin/launchctl bootstrap system /Library/LaunchDaemons/*dev.tuist.xcode-processor*
      github-actions ALL=(ALL) NOPASSWD: /bin/launchctl kickstart -k system/dev.tuist.xcode-processor
    '';
    mode = "0440";
  };

  # Caddy reverse proxy (TLS termination)
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

  # Xcode processor service
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

  # Users
  users.users.xcode-processor = {
    home = "/Users/xcode-processor";
    shell = pkgs.zsh;
    isHidden = true;
  };

  users.users.github-actions = {
    home = "/Users/github-actions";
    shell = pkgs.bash;
    openssh.authorizedKeys.keys = [
      # Populated via GitHub environment secrets or 1Password
    ];
  };

  nix.enable = false;

  system.stateVersion = 6;
}
