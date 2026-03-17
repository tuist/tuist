defmodule Tuist.IngestRepo.Migrations.RenameShardSessionsToShardPlans do
  @moduledoc """
  Renames shard_sessions table to shard_plans and
  shard_session_id column in test_runs to shard_plan_id.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("RENAME TABLE shard_sessions TO shard_plans")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("ALTER TABLE test_runs RENAME COLUMN `shard_session_id` TO `shard_plan_id`")
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("ALTER TABLE test_runs RENAME COLUMN `shard_plan_id` TO `shard_session_id`")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("RENAME TABLE shard_plans TO shard_sessions")
  end
end
