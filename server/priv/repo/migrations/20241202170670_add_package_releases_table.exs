defmodule Tuist.Repo.Migrations.AddPackageReleasesTable do
  use Ecto.Migration

  def change do
    create table(:package_releases, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add(:package_id, references(:packages, type: :uuid, on_delete: :delete_all), null: false)
      add :checksum, :string, null: false
      add :version, :string, null: false
      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:package_releases, [:package_id, :version])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:package_releases, [:package_id])
  end
end
