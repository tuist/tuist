defmodule Tuist.Repo.Migrations.AddCacheVolumeImagePublication do
  use Ecto.Migration

  def change do
    alter table(:runner_cache_volume_uses) do
      # PostgreSQL 16 stores this constant default without rewriting existing rows.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :base_generation, :bigint, null: false, default: 0
      add :image_digest, :string
      add :content_digest, :string
      add :published_generation, :bigint
    end
  end
end
