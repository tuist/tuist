defmodule Tuist.IngestRepo.Migrations.RenamePlanIdToReference do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE shard_plans RENAME COLUMN plan_id TO reference")
    execute("ALTER TABLE shard_plan_modules RENAME COLUMN plan_id TO reference")
    execute("ALTER TABLE shard_plan_test_suites RENAME COLUMN plan_id TO reference")
    execute("ALTER TABLE shard_runs RENAME COLUMN plan_id TO reference")
  end

  def down do
    execute("ALTER TABLE shard_plans RENAME COLUMN reference TO plan_id")
    execute("ALTER TABLE shard_plan_modules RENAME COLUMN reference TO plan_id")
    execute("ALTER TABLE shard_plan_test_suites RENAME COLUMN reference TO plan_id")
    execute("ALTER TABLE shard_runs RENAME COLUMN reference TO plan_id")
  end
end
