defmodule Tuist.IngestRepo.Migrations.AddStateToTestCases do
  use Ecto.Migration

  def change do
    alter table(:test_cases) do
      add :state, :"LowCardinality(String)", default: "enabled"
    end
  end
end
