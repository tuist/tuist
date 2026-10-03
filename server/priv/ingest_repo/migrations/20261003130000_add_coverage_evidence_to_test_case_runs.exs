defmodule Tuist.IngestRepo.Migrations.AddCoverageEvidenceToTestCaseRuns do
  @moduledoc """
  Records, per test case run, what the run's per-test coverage evidence holds
  for the test: `own` when it recorded the test's own evidence (a `test`
  scope in `coverage_files`), `overlapped` when it recorded the test only as
  overlapping another test of its process (Swift Testing running in
  parallel), so nothing could be attributed to it, and `none` otherwise.

  A test case's newest evidence is then one read of its runs in key order
  instead of a search through its recent runs' evidence, and a skipped test
  without evidence of its own can tell an overlap from a missing attribution
  trait. Existing parts read the default until a merge rewrites them, and a
  mostly `none` column compresses to almost nothing under ZSTD.
  """
  use Ecto.Migration

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_case_runs
    ADD COLUMN IF NOT EXISTS coverage_evidence Enum8('none' = 0, 'own' = 1, 'overlapped' = 2) DEFAULT 'none' CODEC(ZSTD(1))
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs DROP COLUMN IF EXISTS coverage_evidence"
  end
end
