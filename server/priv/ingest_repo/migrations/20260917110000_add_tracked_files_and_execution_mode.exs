defmodule Tuist.IngestRepo.Migrations.AddTrackedFilesAndExecutionMode do
  @moduledoc """
  Two pieces of evidence test selection needs from the first coverage runs
  on: the tracked files a run saw (dependency manifests, generator config,
  fixtures and snapshots, matched by the project's globs) with the blob each
  had, so a later run can only reuse a run's evidence when every tracked
  file is identical; and whether tests executed in parallel or serially, per
  run and per target, so the serial cost of per-test attribution can be
  weighed against history.
  """
  use Ecto.Migration

  alias Tuist.Environment

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute("""
    ALTER TABLE test_runs
      ADD COLUMN IF NOT EXISTS tracked_files_truncated Bool DEFAULT false,
      ADD COLUMN IF NOT EXISTS execution_mode LowCardinality(String) DEFAULT ''
    """)

    execute("""
    ALTER TABLE test_module_runs
      ADD COLUMN IF NOT EXISTS execution_mode LowCardinality(String) DEFAULT ''
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS test_run_tracked_files
    (
      `project_id` Int64,
      `test_run_id` UUID,
      `path` String,
      `git_blob_id` String DEFAULT '',
      `inserted_at` DateTime64(6) DEFAULT now()
    )
    ENGINE = ReplacingMergeTree(inserted_at)
    PARTITION BY toYYYYMM(inserted_at)
    ORDER BY (project_id, test_run_id, path)
    TTL toDateTime(inserted_at) + INTERVAL #{Environment.coverage_retention_days().files} DAY
    """)
  end

  def down do
    execute("DROP TABLE IF EXISTS test_run_tracked_files")
    execute("ALTER TABLE test_module_runs DROP COLUMN IF EXISTS execution_mode")

    execute("""
    ALTER TABLE test_runs
      DROP COLUMN IF EXISTS tracked_files_truncated,
      DROP COLUMN IF EXISTS execution_mode
    """)
  end
end
