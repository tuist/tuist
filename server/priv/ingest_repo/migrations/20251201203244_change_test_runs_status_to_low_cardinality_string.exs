defmodule Tuist.IngestRepo.Migrations.ChangeTestRunsStatusToLowCardinalityString do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE test_runs DROP INDEX IF EXISTS idx_status SETTINGS mutations_sync = 1")

    execute(
      "ALTER TABLE test_runs MODIFY COLUMN status LowCardinality(String) SETTINGS mutations_sync = 1"
    )

    execute("ALTER TABLE test_runs ADD INDEX idx_status (status) TYPE set(3) GRANULARITY 1")
  end

  def down do
    execute("ALTER TABLE test_runs DROP INDEX IF EXISTS idx_status SETTINGS mutations_sync = 1")

    execute(
      "ALTER TABLE test_runs MODIFY COLUMN status Enum8('success' = 0, 'failure' = 1) SETTINGS mutations_sync = 1"
    )

    execute("ALTER TABLE test_runs ADD INDEX idx_status (status) TYPE set(2) GRANULARITY 1")
  end
end
