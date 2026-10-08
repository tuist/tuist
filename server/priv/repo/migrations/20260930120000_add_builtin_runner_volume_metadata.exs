defmodule Tuist.Repo.Migrations.AddBuiltinRunnerVolumeMetadata do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  # PostgreSQL 16 adds constant defaults without rewriting existing rows.
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety
  def change do
    alter table(:runner_cache_volumes) do
      add :builtin_name, :text
    end

    alter table(:runner_cache_volume_uses) do
      add :superseded_at, :timestamptz
    end

    alter table(:runner_cache_volume_measurements) do
      add :retired, :boolean, default: false, null: false
    end

    create unique_index(:runner_cache_volumes, [:account_id, :builtin_name], concurrently: true)
  end
end
