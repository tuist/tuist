defmodule Tuist.Repo.Migrations.CreateArtifactRetentionCursors do
  use Ecto.Migration

  def change do
    create table(:artifact_retention_cursors, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :artifact_type, :string, null: false
      add :after_inserted_at, :timestamptz, null: false
      add :after_id, :string, null: false

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:artifact_retention_cursors, [:account_id, :artifact_type])
  end
end
