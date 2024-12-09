defmodule Tuist.Repo.Migrations.AddPackagesTable do
  use Ecto.Migration

  def change do
    create table(:packages, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :scope, :citext, null: false
      add :name, :citext, null: false
      add :last_updated_releases_at, :timestamptz
      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:packages, [:scope, :name])
  end
end
