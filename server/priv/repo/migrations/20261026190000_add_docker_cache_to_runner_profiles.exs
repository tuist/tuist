defmodule Tuist.Repo.Migrations.AddDockerCacheToRunnerProfiles do
  use Ecto.Migration

  # Databases where this ran under its earlier version already have the column.
  def up do
    alter table(:runner_profiles) do
      # PostgreSQL 16 stores this constant default without rewriting existing rows.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add_if_not_exists :docker_cache, :boolean, null: false, default: true
    end
  end

  def down do
    alter table(:runner_profiles) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove_if_exists :docker_cache, :boolean
    end
  end
end
