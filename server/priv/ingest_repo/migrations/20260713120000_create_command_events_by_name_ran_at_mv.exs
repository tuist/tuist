defmodule Tuist.IngestRepo.Migrations.CreateCommandEventsByNameRanAtMv do
  @moduledoc """
  Creates `command_events_by_name_ran_at`, a materialized view sorted by
  `(project_id, name, ran_at)` for the name-filtered "recent runs" list queries
  (cache runs, generate runs, the `/runs` API when a name filter is present).

  These queries filter a single `name` (e.g. `name = 'cache'`) and page by
  `ran_at DESC`. `command_events_by_ran_at` is sorted by `(project_id, ran_at)`
  only, so `name` is applied as a predicate while ClickHouse scans in `ran_at`
  order. When the filtered command is a small fraction of a project's events
  (e.g. `cache` is ~0.08% of a high-volume project), collecting a page of N rows
  scans deep into history — up to the whole project. Production showed a single
  page reading ~16M rows / ~12 GiB (p90 ~7.6s).

  With `name` in the sort key, `(project_id, name)` is a contiguous range and
  `ran_at` is ordered within it, so `ran_at DESC LIMIT N` reads ~one granule via
  reverse read-in-order regardless of how sparse the command is. The same
  production page reads ~75K rows / ~127 MiB (~209ms) against this layout.

  The view is intentionally NOT partitioned. `command_events` is partitioned by
  `toYYYYMM(ran_at)`, which fans a reverse read-in-order scan across every
  monthly part (a tail granule each); an unpartitioned view keeps the
  `(project_id, name)` range in one contiguous run of parts.

  `command_events_by_ran_at` (project_id, ran_at) is kept for the no-name
  `ran_at`-ordered queries (e.g. ModuleCacheLive recent runs, the `/runs` API
  without a name filter), which rely on read-in-order over `ran_at` directly.

  The `idx_name` bloom filter is dropped here because `name` leads the sort key.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    CREATE MATERIALIZED VIEW IF NOT EXISTS command_events_by_name_ran_at (
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
      INDEX idx_is_ci is_ci TYPE minmax GRANULARITY 128,
      INDEX idx_user_id user_id TYPE minmax GRANULARITY 32,
      INDEX idx_cacheable_targets_count cacheable_targets_count TYPE minmax GRANULARITY 16
    )
    ENGINE = MergeTree
    ORDER BY (project_id, name, ran_at)
    SETTINGS index_granularity = 8192
    POPULATE
    AS SELECT * FROM command_events
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "DROP VIEW IF EXISTS command_events_by_name_ran_at SYNC"
  end
end
