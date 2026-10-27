defmodule Tuist.Repo.Migrations.CreateKuraRegisteredEndpoints do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  def change do
    create table(:kura_registered_endpoints, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :account_id, references(:accounts, on_delete: :delete_all, type: :integer), null: false
      add :node_id, :string, null: false
      add :region, :string
      add :advertised_http_url, :string, null: false
      add :ready, :boolean, null: false, default: false
      add :version, :string
      add :traffic_state, :string
      add :last_heartbeat_at, :timestamptz, null: false
      add :expires_at, :timestamptz, null: false

      timestamps(type: :timestamptz)
    end

    create unique_index(:kura_registered_endpoints, [:account_id, :node_id])
    create index(:kura_registered_endpoints, [:account_id, :expires_at])
  end
end
