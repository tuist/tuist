defmodule Tuist.Repo.Migrations.CreateUserMcpServers do
  use Ecto.Migration

  def change do
    create table(:user_mcp_servers, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :url, :text, null: false
      # Discovered OAuth configuration, kept so refreshes skip discovery.
      add :resource, :text
      add :issuer, :text
      add :authorization_endpoint, :text
      add :token_endpoint, :text
      add :scope, :text
      add :client_id, :text
      add :client_secret, :binary
      add :access_token, :binary
      add :refresh_token, :binary
      add :expires_at, :timestamptz
      add :refreshing_until, :timestamptz
      add :pending_authorization, :binary
      add :pending_state_hash, :binary
      add :pending_expires_at, :timestamptz

      timestamps(type: :timestamptz)
    end

    # The table is created empty in the same transaction; no existing
    # readers or writers can be blocked while its indexes are built.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:user_mcp_servers, [:user_id, :url])

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:user_mcp_servers, [:pending_state_hash],
             where: "pending_state_hash IS NOT NULL"
           )
  end
end
