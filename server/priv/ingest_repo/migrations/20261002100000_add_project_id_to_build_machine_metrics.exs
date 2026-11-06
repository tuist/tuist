defmodule Tuist.IngestRepo.Migrations.AddProjectIdToBuildMachineMetrics do
  use Ecto.Migration

  # Samples were keyed by the build's identifier alone, and the client chooses
  # that identifier. The project lets a reader ask for the samples of a build
  # in its project. Null on rows written before this column existed.
  def up do
    execute """
    ALTER TABLE build_machine_metrics
      ADD COLUMN IF NOT EXISTS project_id Nullable(Int64)
    """
  end

  def down do
    execute "ALTER TABLE build_machine_metrics DROP COLUMN IF EXISTS project_id"
  end
end
