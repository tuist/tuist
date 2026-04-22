defmodule Tuist.IngestRepo.Migrations.DropIsQuarantinedFromTestCases do
  use Ecto.Migration

  # `state` replaces the legacy boolean. The add_state_to_test_cases migration
  # already backfilled `state = 'muted' WHERE is_quarantined = true`, and
  # the TestCase Ecto schema no longer declares the field.
  #
  # excellent_migrations:safety-assured-for-next-line column_removed
  def up do
    execute("ALTER TABLE test_cases DROP COLUMN IF EXISTS is_quarantined")
  end

  def down do
    execute("ALTER TABLE test_cases ADD COLUMN IF NOT EXISTS is_quarantined Bool DEFAULT false")
    execute("ALTER TABLE test_cases UPDATE is_quarantined = (state = 'muted')")
  end
end
