defmodule Tuist.Repo.Migrations.AddTechnologyToAccountCacheEndpoints do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  def change do
    alter table(:account_cache_endpoints) do
      add :technology, :integer, null: false, default: 0
    end

    drop_if_exists index(:account_cache_endpoints, [:account_id, :url])

    create unique_index(:account_cache_endpoints, [:account_id, :technology, :url])
  end
end
