defmodule Tuist.IngestRepo.Migrations.AddSkippedTestModuleStatus do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE test_module_runs MODIFY COLUMN status Enum8('success' = 0, 'failure' = 1, 'skipped' = 2) SETTINGS mutations_sync = 1"
    )
  end

  def down do
    execute(
      "ALTER TABLE test_module_runs MODIFY COLUMN status Enum8('success' = 0, 'failure' = 1) SETTINGS mutations_sync = 1"
    )
  end
end
