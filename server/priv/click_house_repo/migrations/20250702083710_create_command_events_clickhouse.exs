defmodule Tuist.ClickHouseRepo.Migrations.CreateCommandEventsClickhouse do
  use Ecto.Migration

  def up do
    # In production, these are created by Clickhouse Pipes.
    if Tuist.Environment.dev?() || Tuist.Environment.test?() do
      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      execute """
      CREATE TABLE command_events
      (
          `id` UUID,
          `legacy_id` Int64 DEFAULT abs(rand64()),
          `legacy_artifact_path` Bool DEFAULT false,
          `name` String, `subcommand` String,
          `command_arguments` String,
          `duration` Int32,
          `client_id` String,
          `tuist_version` String,
          `swift_version` String,
          `macos_version` String,
          `project_id` Int64,
          `created_at` DateTime64(6),
          `updated_at` DateTime64(6),
          `cacheable_targets` Array(String),
          `local_cache_target_hits` Array(String),
          `remote_cache_target_hits` Array(String),
          `is_ci` Bool,
          `test_targets` Array(String),
          `local_test_target_hits` Array(String),
          `remote_test_target_hits` Array(String),
          `status` Int32,
          `error_message` String,
          `user_id` Int32,
          `remote_cache_target_hits_count` Int32,
          `remote_test_target_hits_count` Int32,
          `git_commit_sha` String,
          `git_ref` String,
          `preview_id` UUID,
          `git_branch` String,
          `ran_at` DateTime64(6),
          `build_run_id` UUID,
          `_peerdb_synced_at` DateTime64(9) DEFAULT now64(),
          `_peerdb_is_deleted` Int8,
          `_peerdb_version` Int64
      )
      ENGINE = MergeTree
      PRIMARY KEY (created_at, id)
      ORDER BY (created_at, id)
      SETTINGS index_granularity = 8192
      """
    else
      :ok
    end
  end

  def down do
    drop table(:command_events)
  end
end
