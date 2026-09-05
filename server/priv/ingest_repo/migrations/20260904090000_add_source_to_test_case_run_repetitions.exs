defmodule Tuist.IngestRepo.Migrations.AddSourceToTestCaseRunRepetitions do
  use Ecto.Migration

  def up do
    alter table(:test_case_run_repetitions) do
      add :source, :"LowCardinality(String)", default: "run"
    end
  end

  def down do
    alter table(:test_case_run_repetitions) do
      remove :source
    end
  end
end
