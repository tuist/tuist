defmodule Tuist.IngestRepo.Migrations.ChangeShardPlanIdToUuidAndMergeTree do
  @moduledoc """
  Changes test_runs.shard_plan_id from String to Nullable(UUID) so it
  can reference ShardPlan.id directly, enabling standard Ecto preloads.

  Also recreates shard_plans with MergeTree instead of ReplacingMergeTree
  since plans are now created once and never updated.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("ALTER TABLE test_runs MODIFY COLUMN `shard_plan_id` Nullable(UUID)")

    # Recreate shard_plans with MergeTree engine.
    # ClickHouse doesn't support ALTER TABLE ... ENGINE, so we rename, create, insert, drop.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("RENAME TABLE shard_plans TO shard_plans_old")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    CREATE TABLE IF NOT EXISTS shard_plans
    (
      `id` UUID,
      `plan_id` String,
      `project_id` Int64,
      `shard_count` Int32,
      `granularity` LowCardinality(String) DEFAULT 'module',
      `inserted_at` DateTime64(6)
    )
    ENGINE = MergeTree()
    PARTITION BY toYYYYMM(inserted_at)
    ORDER BY (project_id, plan_id)
    SETTINGS index_granularity = 8192
    """)

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("INSERT INTO shard_plans SELECT * FROM shard_plans_old")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("DROP TABLE shard_plans_old")
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("ALTER TABLE test_runs MODIFY COLUMN `shard_plan_id` String DEFAULT ''")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("RENAME TABLE shard_plans TO shard_plans_old")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    CREATE TABLE IF NOT EXISTS shard_plans
    (
      `id` UUID,
      `plan_id` String,
      `project_id` Int64,
      `shard_count` Int32,
      `granularity` LowCardinality(String) DEFAULT 'module',
      `inserted_at` DateTime64(6)
    )
    ENGINE = ReplacingMergeTree(inserted_at)
    PARTITION BY toYYYYMM(inserted_at)
    ORDER BY (project_id, plan_id)
    SETTINGS index_granularity = 8192
    """)

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("INSERT INTO shard_plans SELECT * FROM shard_plans_old")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("DROP TABLE shard_plans_old")
  end
end
