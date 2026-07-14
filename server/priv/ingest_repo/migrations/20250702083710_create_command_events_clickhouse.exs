defmodule Tuist.ClickHouseRepo.Migrations.CreateCommandEventsClickhouse do
  use Ecto.Migration

  def up do
    # The managed production instance already has this table: ClickHouse Pipes
    # created it when command_events was replicated over from Postgres. Every
    # other database starts empty and needs it created here — including hosted
    # ones, since each preview environment migrates a brand-new ClickHouse.
    # `IF NOT EXISTS` states that directly, instead of inferring it from whether
    # the deployment happens to be hosted.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
     CREATE TABLE IF NOT EXISTS command_events
       (
           `id` UUID,
           `legacy_id` UInt64 DEFAULT abs(rand64()),
           `legacy_artifact_path` Bool DEFAULT false,
           `name` Nullable(String),
           `subcommand` Nullable(String),
           `command_arguments` Nullable(String),
           `duration` Nullable(Int32),
           `client_id` Nullable(String),
           `tuist_version` Nullable(String),
           `swift_version` Nullable(String),
           `macos_version` Nullable(String),
           `project_id` Int64,
           `created_at` DateTime64(6),
           `updated_at` DateTime64(6),
           `cacheable_targets` Array(String),
           `local_cache_target_hits` Array(String),
           `remote_cache_target_hits` Array(String),
           `is_ci` Nullable(Bool) DEFAULT false,
           `test_targets` Array(String),
           `local_test_target_hits` Array(String),
           `remote_test_target_hits` Array(String),
           `status` Nullable(Int32) DEFAULT 0,
           `error_message` Nullable(String),
           `user_id` Nullable(Int32),
           `remote_cache_target_hits_count` Nullable(Int32) DEFAULT 0,
           `remote_test_target_hits_count` Nullable(Int32) DEFAULT 0,
           `git_commit_sha` Nullable(String),
           `git_ref` Nullable(String),
           `preview_id` Nullable(UUID),
           `git_branch` Nullable(String),
           `ran_at` Nullable(DateTime64(6)),
           `build_run_id` Nullable(UUID),
           `_peerdb_synced_at` DateTime64(9) DEFAULT now64(),
           `_peerdb_is_deleted` Int8,
           `_peerdb_version` Int64
       )      ENGINE = MergeTree
      PRIMARY KEY (created_at, id)
      ORDER BY (created_at, id)
      SETTINGS index_granularity = 8192
    """
  end

  def down do
    drop table(:command_events)
  end
end
