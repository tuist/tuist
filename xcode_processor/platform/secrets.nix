{ config, ... }:

{
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  sops.age.sshKeyPaths = [];

  sops.secrets = {
    # Unlocks priv/secrets/<env>.yml.enc baked into the macOS release. Same
    # value the in-cluster Linux server pods read from 1Password via ESO —
    # one secret, one rotation surface for everything in the bundle (S3,
    # ClickHouse, Sentry, Stripe, etc.).
    master_key = {};

    # Postgres role for the xcresult processor. Same `tuist_processor` role
    # as the in-cluster build processor: the SQL grants it needs (oban_jobs,
    # accounts/projects read-only) are already in place from
    # infra/supabase/tuist-processor-role.sql, so no separate role is
    # provisioned for xcresult — the workload looks identical from
    # Postgres' perspective.
    database_url = {};

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
