defmodule Atlas.Repo.Migrations.AddClientCredentialsToMcpOauthSessions do
  use Ecto.Migration

  def change do
    alter table(:mcp_oauth_sessions) do
      add :client_id, :binary
      add :client_secret, :binary
    end
  end
end
