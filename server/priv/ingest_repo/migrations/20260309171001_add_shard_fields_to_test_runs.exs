defmodule Tuist.IngestRepo.Migrations.AddShardFieldsToTestRuns do
  @moduledoc """
  Adds shard_session_id and shard_index columns to test_runs.

  Uses ADD COLUMN IF NOT EXISTS which is lightweight (no mutation) in ClickHouse,
  avoiding potential issues with queued mutations (error 517).
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("ALTER TABLE test_runs ADD COLUMN IF NOT EXISTS `shard_session_id` String DEFAULT ''")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "ALTER TABLE test_runs ADD COLUMN IF NOT EXISTS `shard_index` Nullable(Int32) DEFAULT NULL"
    )
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("ALTER TABLE test_runs DROP COLUMN IF EXISTS `shard_session_id`")
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("ALTER TABLE test_runs DROP COLUMN IF EXISTS `shard_index`")
  end
end
