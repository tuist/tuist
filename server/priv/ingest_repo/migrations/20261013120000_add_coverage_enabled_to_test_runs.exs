defmodule Tuist.IngestRepo.Migrations.AddCoverageEnabledToTestRuns do
  use Ecto.Migration

  # Whether the run was set up to collect code coverage, reported even when
  # selective testing skipped every test and nothing was measured. NULL for
  # runs from clients that don't report it.
  def up do
    execute "ALTER TABLE test_runs ADD COLUMN IF NOT EXISTS coverage_enabled Nullable(Bool)"
  end

  def down do
    execute "ALTER TABLE test_runs DROP COLUMN IF EXISTS coverage_enabled"
  end
end
