defmodule Tuist.Repo.Migrations.DropLuftAiSubscriptionsAndMcpServers do
  use Ecto.Migration

  # Luft keeps people's AI subscriptions and MCP servers in its own database
  # now. The credentials here were encrypted with Tuist's vault key, so they
  # are not copied; people connect them again in Luft.
  def up do
    # excellent_migrations:safety-assured-for-next-line table_dropped
    drop table(:user_ai_subscriptions)
    # excellent_migrations:safety-assured-for-next-line table_dropped
    drop table(:user_mcp_servers)
  end

  def down do
    create table(:user_ai_subscriptions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :access_token, :binary
      add :refresh_token, :binary
      add :expires_at, :timestamptz
      add :pending_login, :binary
      add :pending_expires_at, :timestamptz
      add :next_poll_at, :timestamptz
      add :refreshing_until, :timestamptz
      add :client_id, :string

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:user_ai_subscriptions, [:user_id, :provider])

    create table(:user_mcp_servers, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
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
      add :expires_at, :timestamptz
      add :refreshing_until, :timestamptz
      add :pending_authorization, :binary
      add :pending_state_hash, :binary
      add :pending_expires_at, :timestamptz

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:user_mcp_servers, [:user_id, :url])

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:user_mcp_servers, [:pending_state_hash],
             where: "pending_state_hash IS NOT NULL"
           )
  end
end
