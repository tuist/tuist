defmodule Tuist.IngestRepo.Migrations.AddIsQuarantinedToTestCaseRuns do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE test_case_runs ADD COLUMN IF NOT EXISTS is_quarantined Bool DEFAULT false"
    )
  end

  def down do
    execute("ALTER TABLE test_case_runs DROP COLUMN IF EXISTS is_quarantined")
  end
end
