defmodule Tuist.Repo.Migrations.AddSandboxAllocationWarmBytes do
  use Ecto.Migration

  def change do
    alter table(:sandbox_nodes) do
      # A remote execution worker's share of the compute allocator's
      # fleet-wide floor; NULL from controllers that predate it.
      add :allocation_warm_bytes, :bigint
    end
  end
end
