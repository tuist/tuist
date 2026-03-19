defmodule Tuist.IngestRepo.Migrations.CreateShardTables do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    CREATE TABLE IF NOT EXISTS shard_plans
    (
      `id` UUID,
      `reference` String,
      `project_id` Int64,
      `shard_count` Int32,
      `granularity` LowCardinality(String) DEFAULT 'module',
      `inserted_at` DateTime64(6)
    )
    ENGINE = MergeTree()
    PARTITION BY toYYYYMM(inserted_at)
    ORDER BY (project_id, reference)
    SETTINGS index_granularity = 8192
    """)

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    CREATE TABLE IF NOT EXISTS shard_plan_modules
    (
      `shard_plan_id` UUID,
      `project_id` Int64,
      `shard_index` UInt16,
      `module_name` String,
      `estimated_duration_ms` UInt64 DEFAULT 0,
      `inserted_at` DateTime64(6)
    )
    ENGINE = MergeTree()
    PARTITION BY toYYYYMM(inserted_at)
    ORDER BY (project_id, shard_plan_id, shard_index, module_name)
    SETTINGS index_granularity = 8192
    """)

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    CREATE TABLE IF NOT EXISTS shard_plan_test_suites
    (
      `shard_plan_id` UUID,
      `project_id` Int64,
      `shard_index` UInt16,
      `module_name` String,
      `test_suite_name` String,
      `estimated_duration_ms` UInt64 DEFAULT 0,
      `inserted_at` DateTime64(6)
    )
    ENGINE = MergeTree()
    PARTITION BY toYYYYMM(inserted_at)
    ORDER BY (project_id, shard_plan_id, shard_index, module_name, test_suite_name)
    SETTINGS index_granularity = 8192
    """)

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    CREATE TABLE IF NOT EXISTS shard_runs
    (
      `shard_plan_id` UUID,
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
    ORDER BY (project_id, shard_plan_id, shard_index)
    SETTINGS index_granularity = 8192
    """)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("DROP TABLE IF EXISTS shard_runs")
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("DROP TABLE IF EXISTS shard_plan_test_suites")
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("DROP TABLE IF EXISTS shard_plan_modules")
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("DROP TABLE IF EXISTS shard_plans")
  end
end
