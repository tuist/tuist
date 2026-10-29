defmodule Tuist.IngestRepo.Migrations.AddCargoCacheMetrics do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE cargo_builds ADD COLUMN IF NOT EXISTS cache_metrics String DEFAULT ''")
  end

  def down do
    execute("ALTER TABLE cargo_builds DROP COLUMN IF EXISTS cache_metrics")
  end
end
