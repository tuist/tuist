defmodule Tuist.IngestRepo.Migrations.AddTestPlanToTestRuns do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE test_runs ADD COLUMN IF NOT EXISTS test_plan Nullable(String)")
  end

  def down do
    execute("ALTER TABLE test_runs DROP COLUMN IF EXISTS test_plan")
  end
end
