defmodule Tuist.IngestRepo.Migrations.ReplaceIsQuarantinedWithStateOnTestCases do
  use Ecto.Migration

  def up do
    alter table(:test_cases) do
      add :state, :"LowCardinality(String)", default: "enabled"
    end

    execute(
      "ALTER TABLE test_cases UPDATE state = 'muted' WHERE is_quarantined = true SETTINGS mutations_sync = 2"
    )

    execute("ALTER TABLE test_cases DROP COLUMN IF EXISTS is_quarantined")
  end

  def down do
    execute("ALTER TABLE test_cases ADD COLUMN IF NOT EXISTS is_quarantined Bool DEFAULT false")

    execute(
      "ALTER TABLE test_cases UPDATE is_quarantined = (state = 'muted') WHERE 1 SETTINGS mutations_sync = 2"
    )

    alter table(:test_cases) do
      remove :state
    end
  end
end
