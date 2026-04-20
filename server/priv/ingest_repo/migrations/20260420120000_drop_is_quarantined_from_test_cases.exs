defmodule Tuist.IngestRepo.Migrations.DropIsQuarantinedFromTestCases do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE test_cases DROP COLUMN IF EXISTS is_quarantined")
  end

  def down do
    execute("ALTER TABLE test_cases ADD COLUMN IF NOT EXISTS is_quarantined Bool DEFAULT false")
    execute("ALTER TABLE test_cases UPDATE is_quarantined = (state = 'muted') WHERE 1")
  end
end
