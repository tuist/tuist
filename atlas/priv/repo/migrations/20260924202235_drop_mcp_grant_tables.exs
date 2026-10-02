defmodule Atlas.Repo.Migrations.DropMcpGrantTables do
  use Ecto.Migration

  # The operator grant flow was removed in an earlier release, which kept these
  # tables so pods still running the old code could query them while the
  # rollout was in flight. Migrations run in the new pod's init container, so
  # the drop can only ship once no pod reads them.
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
