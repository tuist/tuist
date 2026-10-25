defmodule Tuist.Repo.Migrations.AddDockerCacheToRunnerProfiles do
  use Ecto.Migration

  def change do
    alter table(:runner_profiles) do
      # PostgreSQL 16 stores this constant default without rewriting existing rows.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :docker_cache, :boolean, null: false, default: true
    end
  end
end
