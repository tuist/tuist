defmodule Tuist.IngestRepo.Migrations.AddDiskSpaceToBuildMachineMetrics do
  use Ecto.Migration

  def change do
    alter table(:build_machine_metrics) do
      add :disk_total_bytes, :"Nullable(Int64)"
      add :disk_available_bytes, :"Nullable(Int64)"
    end
  end
end
