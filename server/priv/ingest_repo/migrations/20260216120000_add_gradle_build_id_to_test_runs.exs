defmodule Tuist.IngestRepo.Migrations.AddGradleBuildIdToTestRuns do
  use Ecto.Migration

  def change do
    alter table(:test_runs) do
      add :gradle_build_id, :"Nullable(UUID)"
    end
  end
end
