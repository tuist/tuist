defmodule Tuist.Repo.Migrations.AddRunnerProfileCacheWriterPolicy do
  use Ecto.Migration

  def change do
    alter table(:runner_profiles) do
      # NULL follows each repository's default branch.
      add :cache_writer_branches, {:array, :string}
    end

    alter table(:runner_cache_volumes) do
      add :default_branch, :string
    end

    alter table(:runner_cache_volume_uses) do
      add :writer_profile_id, :bigint
      # PostgreSQL 16 stores this constant default without rewriting existing rows.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :writer_default_branch, :boolean, null: false, default: false
    end
  end
end
