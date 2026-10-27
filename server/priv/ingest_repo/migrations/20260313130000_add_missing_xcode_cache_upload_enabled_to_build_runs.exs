defmodule Tuist.IngestRepo.Migrations.AddMissingXcodeCacheUploadEnabledToBuildRuns do
  use Ecto.Migration
  alias Tuist.IngestRepo

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    IngestRepo.query!(
      "ALTER TABLE build_runs ADD COLUMN IF NOT EXISTS xcode_cache_upload_enabled Bool DEFAULT false"
    )
  end

  def down do
    :ok
  end
end
