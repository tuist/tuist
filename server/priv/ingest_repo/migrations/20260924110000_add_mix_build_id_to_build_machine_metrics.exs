defmodule Tuist.IngestRepo.Migrations.AddMixBuildIdToBuildMachineMetrics do
  use Ecto.Migration

  def up do
    execute """
    ALTER TABLE build_machine_metrics
      ADD COLUMN IF NOT EXISTS mix_build_id Nullable(UUID)
    """
  end

  def down do
    execute "ALTER TABLE build_machine_metrics DROP COLUMN IF EXISTS mix_build_id"
  end
end
