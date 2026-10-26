defmodule Tuist.Repo.Migrations.AddDrainStartedAtToKuraServers do
  use Ecto.Migration

  def change do
    alter table(:kura_servers) do
      add :drain_started_at, :timestamptz
    end
  end
end
