defmodule Tuist.Repo.Migrations.AddPackageManifests do
  use Ecto.Migration

  def change do
    create table(:package_manifests, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add(:package_release_id, references(:package_releases, type: :uuid, on_delete: :delete_all),
        null: false
      )

      add :swift_version, :string
      add :swift_tools_version, :string
      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:package_manifests, [:package_release_id, :swift_version])
  end
end
