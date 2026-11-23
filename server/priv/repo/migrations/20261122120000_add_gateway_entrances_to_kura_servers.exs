defmodule Tuist.Repo.Migrations.AddGatewayEntrancesToKuraServers do
  use Ecto.Migration

  def change do
    alter table(:kura_servers) do
      add :gateway_entrances, :map
    end
  end
end
