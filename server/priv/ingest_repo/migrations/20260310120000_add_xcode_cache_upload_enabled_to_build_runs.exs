defmodule Tuist.IngestRepo.Migrations.AddXcodeCacheUploadEnabledToBuildRuns do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE build_runs ADD COLUMN IF NOT EXISTS `xcode_cache_upload_enabled` Bool DEFAULT false
    """)
  end

  def down do
    execute("""
    ALTER TABLE build_runs DROP COLUMN IF EXISTS `xcode_cache_upload_enabled`
    """)
  end
end
