defmodule Tuist.IngestRepo.Migrations.AddCoverageEvidenceStatusToTestRuns do
  @moduledoc """
  Whether a run collected per-test coverage evidence: `collected`,
  `not_linked` (asked for, but no test process recorded any, so no target
  links TestCoverageAttribution), `failed`, or empty when the run didn't ask.
  What tells a skipped test's missing evidence apart (`gap_reasons` on
  `coverage_commits`).
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute(
      "ALTER TABLE test_runs ADD COLUMN IF NOT EXISTS coverage_evidence_status LowCardinality(String) DEFAULT ''"
    )
  end

  def down do
    execute("ALTER TABLE test_runs DROP COLUMN IF EXISTS coverage_evidence_status")
  end
end
