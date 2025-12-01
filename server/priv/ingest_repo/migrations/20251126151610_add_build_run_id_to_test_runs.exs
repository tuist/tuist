defmodule Tuist.IngestRepo.Migrations.AddBuildRunIdToTestRuns do
  use Ecto.Migration

  def change do
    alter table(:test_runs) do
      add :build_run_id, :uuid
    end
  end
end
