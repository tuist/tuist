defmodule Tuist.IngestRepo.Migrations.AddShardFieldsToExistingTables do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # test_runs
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "ALTER TABLE test_runs ADD COLUMN IF NOT EXISTS `shard_plan_id` Nullable(UUID) DEFAULT NULL"
    )

    # test_case_runs
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "ALTER TABLE test_case_runs ADD COLUMN IF NOT EXISTS `shard_id` Nullable(UUID) DEFAULT NULL"
    )

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "ALTER TABLE test_case_runs ADD COLUMN IF NOT EXISTS `shard_index` Nullable(Int32) DEFAULT NULL"
    )

    # test_module_runs
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "ALTER TABLE test_module_runs ADD COLUMN IF NOT EXISTS `shard_id` Nullable(UUID) DEFAULT NULL"
    )

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "ALTER TABLE test_module_runs ADD COLUMN IF NOT EXISTS `shard_index` Nullable(Int32) DEFAULT NULL"
    )

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "ALTER TABLE test_module_runs ADD COLUMN IF NOT EXISTS `selective_testing_hash` Nullable(String) DEFAULT NULL"
    )

    # test_suite_runs
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "ALTER TABLE test_suite_runs ADD COLUMN IF NOT EXISTS `shard_id` Nullable(UUID) DEFAULT NULL"
    )

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "ALTER TABLE test_suite_runs ADD COLUMN IF NOT EXISTS `shard_index` Nullable(Int32) DEFAULT NULL"
    )
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("ALTER TABLE test_runs DROP COLUMN IF EXISTS `shard_plan_id`")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("ALTER TABLE test_case_runs DROP COLUMN IF EXISTS `shard_id`")
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("ALTER TABLE test_case_runs DROP COLUMN IF EXISTS `shard_index`")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("ALTER TABLE test_module_runs DROP COLUMN IF EXISTS `shard_id`")
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("ALTER TABLE test_module_runs DROP COLUMN IF EXISTS `shard_index`")
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("ALTER TABLE test_module_runs DROP COLUMN IF EXISTS `selective_testing_hash`")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("ALTER TABLE test_suite_runs DROP COLUMN IF EXISTS `shard_id`")
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("ALTER TABLE test_suite_runs DROP COLUMN IF EXISTS `shard_index`")
  end
end
