defmodule Atlas.Repo.Migrations.CreateMcpToolApprovals do
  use Ecto.Migration

  def change do
    create table(:mcp_tool_approvals, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :server_name, :string, null: false
      add :tool_name, :string, null: false
      add :arguments, :map, null: false, default: %{}
      add :arguments_digest, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :decided_at, :timestamptz
      add :consumed_at, :timestamptz
      add :expires_at, :timestamptz, null: false

      timestamps(type: :timestamptz)
    end

    create index(:mcp_tool_approvals, [:user_id, :server_name, :tool_name, :arguments_digest])
    create index(:mcp_tool_approvals, [:user_id, :status])
  end
end
