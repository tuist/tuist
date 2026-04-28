{ config, pkgs, ... }:

let
  deployDir = "/Users/xcode-processor/xcode_processor";
  currentRelease = "${deployDir}/current";

  # The xcresult processor is the *server* release boot in xcresult-processor
  # mode on macOS. `tuist start` boots the Tuist supervision tree; the BEAM
  # narrows Oban to `:process_xcresult` only via TUIST_XCRESULT_PROCESSOR_MODE
  # below, so this host claims test-result parses and nothing else. No
  # Phoenix endpoint binds (TUIST_WEB=0); liveness is the launchd job staying
  # up + Oban heartbeats into oban_peers.
  envScript = pkgs.writeScript "xcresult-processor-env" ''
    #!/bin/bash
    export RELEASE_NAME="tuist"

    # Boot mode: queue-only consumer for :process_xcresult.
    export TUIST_XCRESULT_PROCESSOR_MODE="1"
    export TUIST_WEB="0"
    export TUIST_HOSTED="1"
    export TUIST_LOG_LEVEL="info"

    # ${config.networking.hostName} is one of xcresult-processor-{staging,canary,production}.
    # Map it to the env that selects priv/secrets/<env>.yml.enc.
    case "${config.networking.hostName}" in
      *-production) export TUIST_DEPLOY_ENV="prod" ;;
      *-canary)     export TUIST_DEPLOY_ENV="can"  ;;
      *-staging)    export TUIST_DEPLOY_ENV="stag" ;;
      *)            export TUIST_DEPLOY_ENV="prod" ;;
    esac

    # MASTER_KEY unlocks the encrypted priv/secrets/<env>.yml.enc bundle
    # (S3 creds, ClickHouse URL, Sentry DSN, etc.) — same flow as the
    # in-cluster server pods.
    export MASTER_KEY="$(cat ${config.sops.secrets.master_key.path})"

    # Override the bundle's DATABASE_URL with the least-privilege
    # tuist_processor role URL (Supabase pooler, transaction-mode 6543).
    # TUIST_DATABASE_POOLED switches Postgrex to `prepare: :unnamed` and
    # drops the tcp_keepalives_* startup parameters Supavisor rejects.
    export DATABASE_URL="$(cat ${config.sops.secrets.database_url.path})"
    export TUIST_DATABASE_POOLED="1"

    # Per-pod Oban concurrency for :process_xcresult. M2-L Mac minis comfortably
    # parse 4 xcresult bundles in parallel — bump if traffic warrants.
    export TUIST_PROCESS_XCRESULT_QUEUE_CONCURRENCY="4"

    # OTel traces forward to the local Alloy receiver, which fans out to
    # Grafana Cloud (see alloy.nix). PromEx /metrics on :9091 is scraped
    # by the same Alloy instance.
    export TUIST_OTEL_EXPORTER_OTLP_ENDPOINT="http://127.0.0.1:4317"

    export GIT_SHA="$(cat ${currentRelease}/.git_sha 2>/dev/null || echo unknown)"

    exec ${currentRelease}/bin/tuist start
  '';
in
{
  services.openssh.enable = true;

  environment.systemPackages = with pkgs; [
    curl
    git
    openssl
  ];

  system.activationScripts.postActivation.text = ''
    # Erlang release is built on CI where OpenSSL is at the Homebrew path.
    # Create a symlink so the binary finds it without needing Homebrew.
    mkdir -p /opt/homebrew/opt/openssl@3/lib
    ln -sf ${pkgs.openssl.out}/lib/libcrypto*.dylib /opt/homebrew/opt/openssl@3/lib/ 2>/dev/null || true
    ln -sf ${pkgs.openssl.out}/lib/libssl*.dylib /opt/homebrew/opt/openssl@3/lib/ 2>/dev/null || true
    mkdir -p /var/log/xcresult-processor /var/log/grafana-alloy
    mkdir -p ${deployDir}/releases
    chown -R github-actions:staff ${deployDir}
  '';

  # The launchd job name kept its historical `xcode-processor` string so the
  # existing nix-darwin state on the Mac minis (sudoers entry, plist path)
  # rolls forward without manual intervention. The release running underneath
  # is the Tuist server in xcresult-processor mode.
  environment.etc."sudoers.d/xcode-processor-deploy".text = ''
    github-actions ALL=(ALL) NOPASSWD: /bin/launchctl bootout system/org.nixos.dev.tuist.xcode-processor
    github-actions ALL=(ALL) NOPASSWD: /bin/launchctl bootstrap system /Library/LaunchDaemons/org.nixos.dev.tuist.xcode-processor.plist
    github-actions ALL=(ALL) NOPASSWD: /bin/launchctl kickstart -k system/org.nixos.dev.tuist.xcode-processor
  '';

  launchd.daemons."dev.tuist.xcode-processor" = {
    serviceConfig = {
      ProgramArguments = [ "${envScript}" ];
      KeepAlive = true;
      RunAtLoad = true;
      StandardOutPath = "/var/log/xcresult-processor/stdout.log";
      StandardErrorPath = "/var/log/xcresult-processor/stderr.log";
      WorkingDirectory = deployDir;
    };
  };

  nix.enable = false;

  system.stateVersion = 6;
}
