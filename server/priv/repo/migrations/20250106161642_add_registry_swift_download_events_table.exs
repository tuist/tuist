defmodule Tuist.Repo.Migrations.PackageDownloadEventsTable do
  use Ecto.Migration

  def change do
    create table(:package_download_events, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :package_release_id, references(:package_releases, type: :uuid, on_delete: :nilify_all),
        null: true

      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:package_download_events, [:account_id])
  end
end
