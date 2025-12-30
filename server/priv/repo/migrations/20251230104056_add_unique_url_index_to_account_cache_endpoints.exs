defmodule Tuist.Repo.Migrations.AddUniqueUrlIndexToAccountCacheEndpoints do
  use Ecto.Migration

  def change do
    create unique_index(:account_cache_endpoints, [:account_id, :url])
  end
end
