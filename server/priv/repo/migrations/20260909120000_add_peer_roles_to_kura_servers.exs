defmodule Tuist.Repo.Migrations.AddPeerRolesToKuraServers do
  use Ecto.Migration

  def up do
    alter table(:kura_servers) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :peer_roles, {:array, :map}, null: false, default: []
    end
  end

  def down do
    alter table(:kura_servers) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :peer_roles
    end
  end
end
