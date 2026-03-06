defmodule Tuist.IngestRepo.Migrations.AddIndexesToCommandEventsByRanAt do
  @moduledoc """
  Recreates `command_events_by_ran_at` with secondary indexes.

  ClickHouse does not support ALTER INDEX on implicit-storage materialized
  views, so we must drop and recreate with explicit column + INDEX definitions.

  Indexes added:

  - `idx_user_id` (minmax): user_id filtering currently scans 844K avg rows
  - `idx_is_ci` (minmax): is_ci filtering currently scans 319K avg rows
  - `idx_name` (bloom_filter): name IN (...) filtering
  - `idx_cacheable_targets_count` (minmax): cacheable_targets_count > 0
    filtering for ModuleCacheLive queries routed to this MV
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "DROP VIEW IF EXISTS command_events_by_ran_at SYNC"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    CREATE MATERIALIZED VIEW IF NOT EXISTS command_events_by_ran_at (
      `id` UUID,
      `legacy_id` UInt64,
      `name` String,
      `subcommand` Nullable(String),
      `command_arguments` Nullable(String),
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
      `status` Nullable(Int32),
      `error_message` Nullable(String),
      `user_id` Nullable(Int32),
      `remote_cache_target_hits_count` Nullable(Int32),
      `remote_test_target_hits_count` Nullable(Int32),
      `git_commit_sha` Nullable(String),
      `git_ref` Nullable(String),
      `preview_id` Nullable(UUID),
      `git_branch` Nullable(String),
      `ran_at` DateTime64(6),
      `build_run_id` Nullable(UUID),
      `cacheable_targets_count` UInt32,
      `local_cache_hits_count` UInt32,
      `remote_cache_hits_count` UInt32,
      `test_targets_count` UInt32,
      `local_test_hits_count` UInt32,
      `remote_test_hits_count` UInt32,
      `hit_rate` Nullable(Float32),
      `test_run_id` Nullable(UUID),
      `cache_endpoint` String,
      INDEX idx_name name TYPE bloom_filter GRANULARITY 4,
      INDEX idx_is_ci is_ci TYPE minmax GRANULARITY 128,
      INDEX idx_user_id user_id TYPE minmax GRANULARITY 32,
      INDEX idx_cacheable_targets_count cacheable_targets_count TYPE minmax GRANULARITY 16
    )
    ENGINE = MergeTree
    ORDER BY (project_id, ran_at)
    SETTINGS index_granularity = 8192
    POPULATE
    AS SELECT * FROM command_events
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "DROP VIEW IF EXISTS command_events_by_ran_at SYNC"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    CREATE MATERIALIZED VIEW IF NOT EXISTS command_events_by_ran_at
    ENGINE = MergeTree
    ORDER BY (project_id, ran_at)
    POPULATE
    AS SELECT * FROM command_events
    """
  end
end
