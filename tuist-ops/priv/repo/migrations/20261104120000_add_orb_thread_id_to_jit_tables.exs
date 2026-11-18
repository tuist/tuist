defmodule TuistOps.Repo.Migrations.AddOrbThreadIdToJitTables do
  use Ecto.Migration

  # `/elevate <env> --thread <id>` elevates one Amp orb thread rather
  # than the requester's own kubectl. Null for every other elevation.
  def change do
    alter table(:tailscale_jit_requests) do
      add :orb_thread_id, :string
    end

    alter table(:tailscale_jit_elevations) do
      add :orb_thread_id, :string
    end
  end
end
