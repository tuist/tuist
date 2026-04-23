defmodule Tuist.IngestRepo.Migrations.AddStateToTestCases do
  use Ecto.Migration

  # Uses raw ALTER TABLE ... ADD COLUMN IF NOT EXISTS so the migration is
  # idempotent. ClickHouse doesn't treat DDL as transactional, so if a prior
  # run added the column but then failed (network blip, replica out of sync,
  # schema_migrations never got the insert), re-running the migration needs
  # to succeed rather than crash with DUPLICATE_COLUMN.
  #
  # The legacy `is_quarantined` column is left in place so this migration is
  # non-destructive. A follow-up migration drops it once this change has
  # shipped and soaked.
  def up do
    execute(
      "ALTER TABLE test_cases ADD COLUMN IF NOT EXISTS state LowCardinality(String) DEFAULT 'enabled'"
    )

    execute("ALTER TABLE test_cases UPDATE state = 'muted' WHERE is_quarantined = true")
  end

  def down do
    execute("ALTER TABLE test_cases DROP COLUMN IF EXISTS state")
  end
end
