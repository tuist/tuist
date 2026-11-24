defmodule Tuist.Repo.Migrations.AddSandboxAllocationSiblingMemoryBytes do
  use Ecto.Migration

  def change do
    alter table(:sandbox_nodes) do
      # The memory of the other carve-out on the host (agent daemon or
      # remote execution worker) the grant was computed with; NULL from
      # controllers that predate it.
      add :allocation_sibling_memory_bytes, :bigint
    end
  end
end
