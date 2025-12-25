defmodule Tuist.Repo.Migrations.AddAccountCacheEndpointsTable do
  use Ecto.Migration

  def change do
    create table(:account_cache_endpoints, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :url, :string, null: false

      timestamps(type: :timestamptz)
    end

    create index(:account_cache_endpoints, [:account_id])
  end
end
