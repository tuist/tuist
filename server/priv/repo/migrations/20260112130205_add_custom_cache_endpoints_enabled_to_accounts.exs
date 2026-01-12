defmodule Tuist.Repo.Migrations.AddCustomCacheEndpointsEnabledToAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :custom_cache_endpoints_enabled, :boolean, default: false, null: false
    end
  end
end
