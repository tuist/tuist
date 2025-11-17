defmodule Cache.Repo.Migrations.CreateCasArtifacts do
  use Ecto.Migration

  def change do
    create table(:cas_artifacts) do
      add :key, :text, null: false
      add :size_bytes, :bigint
      add :last_accessed_at, :utc_datetime_usec, null: false

      timestamps()
    end

    create unique_index(:cas_artifacts, [:key])
    create index(:cas_artifacts, [:last_accessed_at])
  end
end
