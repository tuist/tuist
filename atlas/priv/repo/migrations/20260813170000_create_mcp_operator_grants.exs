defmodule Atlas.Repo.Migrations.CreateMcpOperatorGrants do
  use Ecto.Migration

  # An operator grant elevates an upstream MCP session beyond what the user's
  # own memberships allow. It is short-lived and belongs to one person and one
  # customer account, so it is stored per user and per upstream server, encrypted
  # at rest like the OAuth tokens beside it, and replaced rather than
  # accumulated: an investigation looks at one customer at a time.
  def change do
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
  end
end
