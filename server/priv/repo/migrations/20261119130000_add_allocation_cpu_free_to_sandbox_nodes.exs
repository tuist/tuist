defmodule Tuist.Repo.Migrations.AddAllocationCpuFreeToSandboxNodes do
  use Ecto.Migration

  def change do
    alter table(:sandbox_nodes) do
      # Millicores of the node's allocatable CPU no Pod requests, from the
      # runners-controller's grant. NULL (an older controller) grows no CPU.
      add :allocation_cpu_free_milli, :integer
    end
  end
end
