defmodule Tuist.Repo.Migrations.AddAllocationCpuReclaimableToSandboxNodes do
  use Ecto.Migration

  def change do
    alter table(:sandbox_nodes) do
      # Millicores idle warm runners hold on the node, from the
      # runners-controller's grant: a daemon CPU growth may take them, and
      # the controller retires those runners when the kubelet defers it.
      add :allocation_cpu_reclaimable_milli, :integer
    end
  end
end
