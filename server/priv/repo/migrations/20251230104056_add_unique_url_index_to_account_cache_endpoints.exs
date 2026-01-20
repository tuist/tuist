defmodule Tuist.Repo.Migrations.AddUniqueUrlIndexToAccountCacheEndpoints do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  def change do
    create unique_index(:account_cache_endpoints, [:account_id, :url])
  end
end
