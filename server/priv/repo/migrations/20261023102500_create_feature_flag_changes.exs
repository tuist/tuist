defmodule Tuist.Repo.Migrations.CreateFeatureFlagChanges do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create table(:feature_flag_changes) do
      add :change_id, :uuid, null: false
      add :flag_name, :text, null: false
      add :request, :map, null: false
      add :principal, :map, null: false
      add :before, :map, null: false
      add :after, :map, null: false
      timestamps(type: :timestamptz, updated_at: false)
    end

    create unique_index(:feature_flag_changes, [:change_id], concurrently: true)
    create index(:feature_flag_changes, [:flag_name, :id], concurrently: true)
  end
end
