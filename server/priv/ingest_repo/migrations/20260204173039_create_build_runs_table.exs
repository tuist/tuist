defmodule Tuist.IngestRepo.Migrations.CreateBuildRunsTable do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  @moduledoc """
  Creates the build_runs table in ClickHouse.

  This migration moves build_runs from PostgreSQL/TimescaleDB to ClickHouse for analytics.
  The PostgreSQL table is kept for rollback purposes but will no longer be written to.
  """

  def up do
    execute("""
    CREATE TABLE IF NOT EXISTS build_runs
    (
      `id` UUID,
      `duration` Int32,
      `project_id` Int64,
      `account_id` Int64,
      `macos_version` String DEFAULT '',
      `xcode_version` String DEFAULT '',
      `is_ci` Bool DEFAULT false,
      `model_identifier` String DEFAULT '',
      `scheme` String DEFAULT '',
      `status` LowCardinality(String) DEFAULT '',
      `category` LowCardinality(String) DEFAULT '',
      `configuration` String DEFAULT '',
      `git_branch` String DEFAULT '',
      `git_commit_sha` String DEFAULT '',
      `git_ref` String DEFAULT '',
      `ci_run_id` String DEFAULT '',
      `ci_project_handle` String DEFAULT '',
      `ci_host` String DEFAULT '',
      `ci_provider` LowCardinality(String) DEFAULT '',
      `cacheable_task_remote_hits_count` Int32 DEFAULT 0,
      `cacheable_task_local_hits_count` Int32 DEFAULT 0,
      `cacheable_tasks_count` Int32 DEFAULT 0,
      `custom_tags` Array(String) DEFAULT [],
      `custom_values` Map(String, String) DEFAULT map(),
      `inserted_at` DateTime64(6)
    )
    ENGINE = MergeTree()
    PARTITION BY toYYYYMM(inserted_at)
    ORDER BY (project_id, inserted_at, id)
    SETTINGS index_granularity = 8192
    """)
  end

  def down do
    drop table(:build_runs)
  end
end
