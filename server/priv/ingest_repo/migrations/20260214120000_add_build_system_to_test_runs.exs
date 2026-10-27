defmodule Tuist.IngestRepo.Migrations.AddBuildSystemToTestRuns do
  use Ecto.Migration

  def change do
    alter table(:test_runs) do
      add :build_system, :"LowCardinality(String)", default: "xcode"
    end
  end
end
