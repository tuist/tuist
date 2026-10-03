defmodule Tuist.IngestRepo.Migrations.AddCoverageEvidenceOverlappedToTestCaseRuns do
  @moduledoc """
  Marks the test case runs whose run collected per-test evidence but recorded
  the test only as overlapping another test of its process (Swift Testing
  running in parallel), so nothing could be attributed to it.

  A skipped test without evidence of its own is a gap in the reported
  coverage; with the flag, the gap says the test overlapped another rather
  than lacking the attribution trait. Existing parts read the default until a
  merge rewrites them, and a mostly false column compresses to almost nothing
  under ZSTD.
  """
  use Ecto.Migration

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_case_runs
    ADD COLUMN IF NOT EXISTS coverage_evidence_overlapped Bool DEFAULT false CODEC(ZSTD(1))
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs DROP COLUMN IF EXISTS coverage_evidence_overlapped"
  end
end
