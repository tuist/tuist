defmodule Tuist.Repo.Migrations.AddStableEndpointToKuraServers do
  use Ecto.Migration

  def change do
    alter table(:kura_servers) do
      add :stable_endpoint, :map
    end
  end
end
