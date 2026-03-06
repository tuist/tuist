defmodule Tuist.IngestRepo.Migrations.AddStorageKeyToBuildRuns do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute("""
    ALTER TABLE build_runs ADD COLUMN IF NOT EXISTS `storage_key` Nullable(String) DEFAULT NULL
    """)
  end

  def down do
    execute("""
    ALTER TABLE build_runs DROP COLUMN IF EXISTS `storage_key`
    """)
  end
end
