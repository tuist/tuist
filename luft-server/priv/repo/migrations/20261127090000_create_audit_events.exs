defmodule LuftServer.Repo.Migrations.CreateAuditEvents do
  use Ecto.Migration

  # Who added, authorized or removed an MCP server and who connected or
  # disconnected an AI subscription (`LuftServer.Audit`). Rows are append-only
  # and outlive what they describe, so a removed server can still be traced.
  # Tool calls to an MCP server also record which server they reached.
  def change do
    create table(:audit_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :actor_sub, :text, null: false
      add :action, :text, null: false
      add :owner, :text, null: false
      add :subject_id, :binary_id
      add :details, :map, null: false, default: %{}
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:audit_events, [:owner, :inserted_at])
    create index(:audit_events, [:subject_id])

    alter table(:thread_tool_calls) do
      add :mcp_server_id, :binary_id
      add :mcp_server_owner, :text
      add :mcp_server_host, :text
    end
  end
end
