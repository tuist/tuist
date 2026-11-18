defmodule Tuist.Repo.Migrations.AddSandboxAllocationWarmBytes do
  use Ecto.Migration

  def change do
    alter table(:sandbox_nodes) do
      # A remote execution worker's share of the compute allocator's
      # fleet-wide floor; NULL from controllers that predate it. Staging
      # first ran this under an earlier version, so it may already exist.
      add_if_not_exists :allocation_warm_bytes, :bigint
    end
  end
end
