defmodule Atlas.Repo.Migrations.CreateMcpServerConfigurations do
  use Ecto.Migration

  def change do
    create table(:mcp_server_configurations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :url, :string, null: false
      add :auth_type, :string, null: false, default: "oauth2"
      add :authorization_url, :string
      add :token_url, :string
      add :registration_url, :string
      add :scopes, {:array, :string}, null: false, default: []
      add :read_only, :boolean, null: false, default: true

      timestamps(type: :timestamptz)
    end

    create unique_index(:mcp_server_configurations, [:name])
  end
end
