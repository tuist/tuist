defmodule Tuist.IngestRepo.Migrations.CreateShardPlanModulesAndTestSuites do
  @moduledoc """
  Creates normalized tables for shard plan targets, replacing the
  shard_assignments JSON blob on shard_plans.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    CREATE TABLE IF NOT EXISTS shard_plan_modules
    (
      `plan_id` String,
      `project_id` Int64,
      `shard_index` UInt16,
      `module_name` String,
      `estimated_duration_ms` UInt64,
      `inserted_at` DateTime64(6)
    )
    ENGINE = MergeTree()
    PARTITION BY toYYYYMM(inserted_at)
    ORDER BY (project_id, plan_id, shard_index, module_name)
    SETTINGS index_granularity = 8192
    """)

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    CREATE TABLE IF NOT EXISTS shard_plan_test_suites
    (
      `plan_id` String,
      `project_id` Int64,
      `shard_index` UInt16,
      `module_name` String,
      `test_suite_name` String,
      `estimated_duration_ms` UInt64,
      `inserted_at` DateTime64(6)
    )
    ENGINE = MergeTree()
    PARTITION BY toYYYYMM(inserted_at)
    ORDER BY (project_id, plan_id, shard_index, module_name, test_suite_name)
    SETTINGS index_granularity = 8192
    """)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("DROP TABLE IF EXISTS shard_plan_test_suites")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("DROP TABLE IF EXISTS shard_plan_modules")
  end
end
