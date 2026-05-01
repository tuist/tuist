defmodule Tuist.Repo.Migrations.DropPgArtifactsTableAndReplicationFlag do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety
  # excellent_migrations:safety-assured-for-this-file column_removed
  # excellent_migrations:safety-assured-for-this-file table_dropped
  # excellent_migrations:safety-assured-for-this-file not_concurrent_index
  # excellent_migrations:safety-assured-for-this-file column_added_with_default

  def up do
    alter table(:bundles) do
      remove :artifacts_replicated_to_ch
    end

    drop table(:artifacts)
  end

  def down do
    create table(:artifacts, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :artifact_type, :string, null: false
      add :path, :string, null: false
      add :size, :bigint, null: false
      add :shasum, :string, null: false
      add :bundle_id, references(:bundles, type: :uuid, on_delete: :delete_all), null: false
      add :artifact_id, :uuid

      timestamps(type: :timestamptz)
    end

    create index(:artifacts, [:bundle_id])
    create index(:artifacts, [:artifact_id])
    create index(:artifacts, [:bundle_id, :artifact_id])

    create index(:artifacts, [:bundle_id],
             where: "artifact_id IS NULL",
             name: :artifacts_top_level_index
           )

    alter table(:bundles) do
      add :artifacts_replicated_to_ch, :boolean, default: true, null: false
    end
  end
end
