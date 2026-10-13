defmodule Tuist.Repo.Migrations.AddCacheVolumeWriterPolicy do
  use Ecto.Migration

  def change do
    alter table(:runner_cache_volumes) do
      # PostgreSQL 16 stores this constant default without rewriting existing rows.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :writer_branches, {:array, :string}, null: false, default: []
    end

    alter table(:runner_cache_volume_uses) do
      # PostgreSQL 16 stores this constant default without rewriting existing rows.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :commit_mode, :string, null: false, default: "auto"
    end
  end
end
