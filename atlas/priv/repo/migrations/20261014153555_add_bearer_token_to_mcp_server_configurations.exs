defmodule Atlas.Repo.Migrations.AddBearerTokenToMcpServerConfigurations do
  use Ecto.Migration

  def change do
    alter table(:mcp_server_configurations) do
      add :bearer_token, :binary
    end
  end
end
