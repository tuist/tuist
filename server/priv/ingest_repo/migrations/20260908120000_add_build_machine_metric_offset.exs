defmodule Tuist.IngestRepo.Migrations.AddBuildMachineMetricOffset do
  use Ecto.Migration

  def change do
    alter table(:build_machine_metrics) do
      add :offset_ms, :"Nullable(Float64)"
    end
  end
end
