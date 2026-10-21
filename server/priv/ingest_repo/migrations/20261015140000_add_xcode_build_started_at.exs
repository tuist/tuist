defmodule Tuist.IngestRepo.Migrations.AddXcodeBuildStartedAt do
  use Ecto.Migration

  def change do
    alter table(:build_runs) do
      add :started_at, :"Nullable(DateTime64(6))"
    end
  end
end
