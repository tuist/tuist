defmodule Tuist.IngestRepo.Migrations.RemoveDeprecatedShardPlanColumns do
  @moduledoc """
  Removes columns from shard_plans that are no longer needed:
  - shard_assignments: replaced by shard_plan_modules/shard_plan_test_suites tables
  - upload_completed: no longer tracked (plans only inserted when complete)
  - xctestrun_object_key: CLI handles xctestrun filtering locally
  - bundle_object_key: computed conventionally from account/project/plan_id
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("ALTER TABLE shard_plans DROP COLUMN IF EXISTS `shard_assignments`")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("ALTER TABLE shard_plans DROP COLUMN IF EXISTS `upload_completed`")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("ALTER TABLE shard_plans DROP COLUMN IF EXISTS `xctestrun_object_key`")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("ALTER TABLE shard_plans DROP COLUMN IF EXISTS `bundle_object_key`")
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "ALTER TABLE shard_plans ADD COLUMN IF NOT EXISTS `shard_assignments` String DEFAULT '[]'"
    )

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("ALTER TABLE shard_plans ADD COLUMN IF NOT EXISTS `upload_completed` UInt8 DEFAULT 0")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "ALTER TABLE shard_plans ADD COLUMN IF NOT EXISTS `xctestrun_object_key` String DEFAULT ''"
    )

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "ALTER TABLE shard_plans ADD COLUMN IF NOT EXISTS `bundle_object_key` String DEFAULT ''"
    )
  end
end
