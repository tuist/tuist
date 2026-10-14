defmodule Tuist.Repo.Migrations.AddRunnerProfileCacheWriterPolicy do
  use Ecto.Migration

  def change do
    alter table(:runner_profiles) do
      # PostgreSQL 16 stores these constant defaults without rewriting existing rows.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :cache_writer_branches, {:array, :string}, null: false, default: []
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :cache_any_branch_writes, :boolean, null: false, default: false
    end

    alter table(:runner_cache_volume_uses) do
      add :writer_profile_id, :bigint
    end
  end
end
