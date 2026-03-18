defmodule Tuist.IngestRepo.Migrations.RenameSessionIdToPlanIdInShardPlans do
  @moduledoc "Renames session_id to plan_id in shard_plans table."
  use Ecto.Migration
  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute("ALTER TABLE shard_plans RENAME COLUMN `session_id` TO `plan_id`")
  end

  def down do
    execute("ALTER TABLE shard_plans RENAME COLUMN `plan_id` TO `session_id`")
  end
end
