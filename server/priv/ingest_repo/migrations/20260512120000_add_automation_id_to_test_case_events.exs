defmodule Tuist.IngestRepo.Migrations.AddAutomationIdToTestCaseEvents do
  use Ecto.Migration

  # Attribution column for events produced by an automation acting on a test
  # case. Nullable because user-initiated events (and the legacy `first_run`
  # event) still have no automation context. Existing rows backfill to NULL,
  # which preserves the current "Automatically by Tuist" / "Manually by …"
  # rendering for them.
  def up do
    execute("ALTER TABLE test_case_events ADD COLUMN IF NOT EXISTS automation_id Nullable(UUID)")
  end

  def down do
    execute("ALTER TABLE test_case_events DROP COLUMN IF EXISTS automation_id")
  end
end
