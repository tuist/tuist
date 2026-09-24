defmodule Atlas.Repo.Migrations.DropMcpOperatorGrants do
  use Ecto.Migration

  # Operators read customer accounts through the tuist upstream with Atlas'
  # ServiceAccount identity, so Atlas no longer requests or stores operator
  # grants. The rows were short-lived encrypted bearers with nothing worth
  # keeping, so down recreates the empty tables.
  def up do
    drop table(:mcp_grant_requests)
    drop table(:mcp_operator_grants)
  end

  def down do
    create table(:mcp_operator_grants, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :server_name, :string, null: false
      add :account_handle, :string, null: false
      add :token, :binary, null: false
      add :expires_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:mcp_operator_grants, [:user_id, :server_name])
    create index(:mcp_operator_grants, [:expires_at])

    create table(:mcp_grant_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :server_name, :string, null: false
      add :account_handle, :string, null: false
      add :expires_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:mcp_grant_requests, [:user_id])
    create index(:mcp_grant_requests, [:expires_at])
  end
end
