defmodule Tuist.IngestRepo.Migrations.AddStateToTestCases do
  use Ecto.Migration

  # The is_quarantined column is left in place here so this PR is non-destructive.
  # A follow-up migration drops it once this change has shipped and soaked.
  def up do
    alter table(:test_cases) do
      add :state, :"LowCardinality(String)", default: "enabled"
    end

    execute("ALTER TABLE test_cases UPDATE state = 'muted' WHERE is_quarantined = true")
  end

  def down do
    alter table(:test_cases) do
      remove :state
    end
  end
end
