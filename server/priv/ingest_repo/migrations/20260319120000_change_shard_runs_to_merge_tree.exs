defmodule Tuist.IngestRepo.Migrations.ChangeShardRunsToMergeTree do
  @moduledoc """
  Recreates shard_runs with MergeTree instead of ReplacingMergeTree.
  Shard runs are created once and never updated, so deduplication is unnecessary.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("RENAME TABLE shard_runs TO shard_runs_old")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    CREATE TABLE IF NOT EXISTS shard_runs
    (
      `plan_id` String,
      `project_id` Int64,
      `test_run_id` String,
      `shard_index` UInt16,
      `status` LowCardinality(String),
      `duration` UInt64 DEFAULT 0,
      `ran_at` DateTime64(6),
      `inserted_at` DateTime64(6)
    )
    ENGINE = MergeTree()
    PARTITION BY toYYYYMM(inserted_at)
    ORDER BY (project_id, plan_id, shard_index)
    SETTINGS index_granularity = 8192
    """)

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("INSERT INTO shard_runs SELECT * FROM shard_runs_old")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("DROP TABLE shard_runs_old")
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("RENAME TABLE shard_runs TO shard_runs_old")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    CREATE TABLE IF NOT EXISTS shard_runs
    (
      `plan_id` String,
      `project_id` Int64,
      `test_run_id` String,
      `shard_index` UInt16,
      `status` LowCardinality(String),
      `duration` UInt64 DEFAULT 0,
      `ran_at` DateTime64(6),
      `inserted_at` DateTime64(6)
    )
    ENGINE = ReplacingMergeTree(inserted_at)
    PARTITION BY toYYYYMM(inserted_at)
    ORDER BY (project_id, plan_id, shard_index)
    SETTINGS index_granularity = 8192
    """)

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("INSERT INTO shard_runs SELECT * FROM shard_runs_old")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("DROP TABLE shard_runs_old")
  end
end
