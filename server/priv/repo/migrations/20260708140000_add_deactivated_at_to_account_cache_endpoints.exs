defmodule Tuist.Repo.Migrations.AddDeactivatedAtToAccountCacheEndpoints do
  use Ecto.Migration

  def change do
    alter table(:account_cache_endpoints) do
      add :deactivated_at, :timestamptz
    end
  end
end
