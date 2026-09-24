defmodule Tuist.IngestRepo.Migrations.AddHasCoverageEvidenceToTestCaseRuns do
  @moduledoc """
  Marks the test case runs whose run recorded the test's own coverage
  evidence (a `test` scope in `coverage_files`).

  A test case's page shows what the test executed the last time a run
  recorded it, and most runs do not (no coverage, no observer, or tests
  Swift Testing ran in parallel). With the flag, that run is one read of the
  test's rows in key order instead of a search through its recent runs'
  evidence. Existing parts read the default until a merge rewrites them, and
  a mostly false column compresses to almost nothing under ZSTD.
  """
  use Ecto.Migration

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_case_runs
    ADD COLUMN IF NOT EXISTS has_coverage_evidence Bool DEFAULT false CODEC(ZSTD(1))
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs DROP COLUMN IF EXISTS has_coverage_evidence"
  end
end
