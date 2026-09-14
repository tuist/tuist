defmodule Tuist.IngestRepo.Migrations.AddGradleBuildStartedAt do
  use Ecto.Migration

  def change do
    alter table(:gradle_builds) do
      add :started_at, :"Nullable(DateTime64(6))"
    end
  end
end
