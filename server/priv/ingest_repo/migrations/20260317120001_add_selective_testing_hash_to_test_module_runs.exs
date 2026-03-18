defmodule Tuist.IngestRepo.Migrations.AddSelectiveTestingHashToTestModuleRuns do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "ALTER TABLE test_module_runs ADD COLUMN IF NOT EXISTS `selective_testing_hash` Nullable(String) DEFAULT NULL"
    )
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("ALTER TABLE test_module_runs DROP COLUMN IF EXISTS `selective_testing_hash`")
  end
end
