defmodule Tuist.IngestRepo.Migrations.CreateShardRuns do
  @moduledoc """
  Creates the shard_runs table to track per-shard execution results.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    CREATE TABLE IF NOT EXISTS shard_runs
    (
      `plan_id` String,
      `project_id` Int64,
      `test_run_id` String,
      `shard_index` UInt16,
      `status` LowCardinality(String) DEFAULT 'in_progress',
      `duration` UInt64 DEFAULT 0,
      `ran_at` DateTime64(6),
      `inserted_at` DateTime64(6)
    )
    ENGINE = ReplacingMergeTree(inserted_at)
    PARTITION BY toYYYYMM(inserted_at)
    ORDER BY (project_id, plan_id, shard_index)
    SETTINGS index_granularity = 8192
    """)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("DROP TABLE IF EXISTS shard_runs")
  end
end
