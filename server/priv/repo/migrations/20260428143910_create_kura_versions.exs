defmodule Tuist.Repo.Migrations.CreateKuraVersions do
  use Ecto.Migration

  def change do
    create table(:kura_versions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :version, :string, null: false
      add :released_at, :timestamptz, null: false

      timestamps(type: :timestamptz)
    end

    create unique_index(:kura_versions, [:version])
    create index(:kura_versions, [:released_at])
  end
end
