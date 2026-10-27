defmodule Tuist.Repo.Migrations.AllowReplicatingKuraServerStatus do
  use Ecto.Migration

  # Adds the `:replicating` (5) status: a server whose workload is up on the
  # desired image but whose public endpoint is not serving yet because the pod
  # is still replicating from mesh peers behind the bootstrap gate.
  def up do
    drop constraint(:kura_servers, :kura_servers_status_valid)

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:kura_servers, :kura_servers_status_valid,
             check: "status IN (0, 1, 2, 3, 4, 5)"
           )
  end

  def down do
    drop constraint(:kura_servers, :kura_servers_status_valid)

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:kura_servers, :kura_servers_status_valid,
             check: "status IN (0, 1, 2, 3, 4)"
           )
  end
end
