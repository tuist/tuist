defmodule Tuist.IngestRepo.Migrations.AddGenerationIdToBuildRuns do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE build_runs ADD COLUMN IF NOT EXISTS `generation_id` Nullable(UUID)")
  end

  def down do
    execute("ALTER TABLE build_runs DROP COLUMN IF EXISTS `generation_id`")
  end
end
