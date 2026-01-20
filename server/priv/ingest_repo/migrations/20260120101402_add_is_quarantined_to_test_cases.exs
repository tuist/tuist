defmodule Tuist.IngestRepo.Migrations.AddIsQuarantinedToTestCases do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE test_cases
    ADD COLUMN IF NOT EXISTS is_quarantined Bool DEFAULT false
    """)
  end

  def down do
    execute("""
    ALTER TABLE test_cases
    DROP COLUMN IF EXISTS is_quarantined
    """)
  end
end
