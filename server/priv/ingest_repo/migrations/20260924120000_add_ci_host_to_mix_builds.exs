defmodule Tuist.IngestRepo.Migrations.AddCiHostToMixBuilds do
  use Ecto.Migration

  def up do
    execute """
    ALTER TABLE mix_builds
      ADD COLUMN IF NOT EXISTS ci_host String DEFAULT ''
    """
  end

  def down do
    execute "ALTER TABLE mix_builds DROP COLUMN IF EXISTS ci_host"
  end
end
