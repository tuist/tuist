defmodule LuftServer.Repo.Migrations.CreateMCPServers do
  use Ecto.Migration

  # Remote MCP servers that threads call tools on. `owner` is `user:<sub>` for
  # a person's own servers (their Tuist subject, as in `sessions.user_sub`) or
  # `account:<id>` for servers an organization's admins connect for every
  # member's threads in it. Credential columns are encrypted by
  # `LuftServer.MCPServers.EncryptedBinary`.
  def change do
    create table(:mcp_servers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :owner, :text, null: false
      add :name, :text, null: false
      add :url, :text, null: false
      add :resource, :text
      add :issuer, :text
      add :authorization_endpoint, :text
      add :token_endpoint, :text
      add :scope, :text
      add :client_id, :text
      add :client_secret, :binary
      add :access_token, :binary
      add :refresh_token, :binary
      add :expires_at, :utc_datetime
      add :refreshing_until, :utc_datetime
      add :pending_authorization, :binary
      # SHA-256 of the OAuth `state`, so the completion finds its row.
      add :pending_state_hash, :binary
      add :pending_expires_at, :utc_datetime
      # Sign-ins started in the current window, to bound third-party calls.
      add :authorization_attempts, :integer, null: false, default: 0
      add :authorization_window_started_at, :utc_datetime

      timestamps()
    end

    create unique_index(:mcp_servers, [:owner, :url])
    create unique_index(:mcp_servers, [:pending_state_hash])
  end
end
