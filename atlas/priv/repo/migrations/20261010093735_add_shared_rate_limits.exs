defmodule Atlas.Repo.Migrations.AddSharedRateLimits do
  use Ecto.Migration

  def change do
    create table(:rate_limit_buckets, primary_key: false) do
      add :key_hash, :binary, primary_key: true
      add :attempts, :bigint, null: false
      add :expires_at, :timestamptz, null: false
    end

    create index(:rate_limit_buckets, [:expires_at])
  end
end
