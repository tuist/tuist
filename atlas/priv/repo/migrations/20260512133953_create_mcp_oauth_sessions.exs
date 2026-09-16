defmodule Atlas.Repo.Migrations.CreateMcpOauthSessions do
  use Ecto.Migration

  def change do
    create table(:mcp_oauth_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :server_name, :string, null: false
      add :status, :string, null: false, default: "authorized"
      add :access_token, :binary
      add :refresh_token, :binary
      add :token_type, :string, null: false, default: "Bearer"
      add :scopes, {:array, :string}, null: false, default: []
      add :expires_at, :utc_datetime
      add :last_refreshed_at, :utc_datetime
      add :last_error, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:mcp_oauth_sessions, [:user_id, :server_name])
    create index(:mcp_oauth_sessions, [:server_name])
  end
end
