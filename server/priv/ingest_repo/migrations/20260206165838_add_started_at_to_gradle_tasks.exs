defmodule Tuist.IngestRepo.Migrations.AddStartedAtToGradleTasks do
  use Ecto.Migration

  def change do
    alter table(:gradle_tasks) do
      add :started_at, :"Nullable(DateTime64(3))"
    end
  end
end
