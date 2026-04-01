{ config, ... }:

{
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  sops.age.sshKeyPaths = [];

  sops.secrets = {
    secret_key_base = {};
    webhook_secret = {};
    s3_endpoint = {};
    s3_bucket = {};
    s3_access_key_id = {};
    s3_secret_access_key = {};
    s3_region = {};
    sentry_dsn = {};
    grafana_prometheus_remote_write_url = {};
    grafana_prometheus_remote_write_username = {};
    grafana_prometheus_remote_write_password = {};
    grafana_tempo_url = {};
    grafana_tempo_username = {};
    grafana_tempo_password = {};
    grafana_loki_url = {};
    grafana_loki_username = {};
    grafana_loki_password = {};
  };
}
