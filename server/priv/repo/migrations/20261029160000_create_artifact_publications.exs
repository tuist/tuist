defmodule Tuist.Repo.Migrations.CreateArtifactPublications do
  use Ecto.Migration

  def change do
    alter table(:app_builds) do
      add :artifact_storage_key, :text
    end

    # Survives account deletion to fence cleanup against admitted uploads.
    create table(:artifact_uploads) do
      add :account_id, :bigint, null: false
      add :inserted_at, :timestamptz, null: false
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:artifact_uploads, [:account_id])

    create table(:artifact_publications, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :created_by_account_id, references(:accounts, on_delete: :nilify_all)
      add :key, :string, null: false
      add :intent, :map, null: false
      add :contents, :map, null: false
      add :committed, :boolean, null: false, default: false
      add :projected, :boolean, null: false, default: false
      add :expired, :boolean, null: false, default: false
      timestamps(type: :timestamptz)
    end

    # New table, so neither index can block existing writers.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:artifact_publications, [:project_id, :key])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:artifact_publications, [:inserted_at, :id])
  end
end
