defmodule Tuist.IngestRepo.Migrations.ChangeTestRunsStatusToLowCardinalityString do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE test_runs DROP INDEX idx_status")

    alter table(:test_runs) do
      modify :status, :"LowCardinality(String)"
    end

    execute("ALTER TABLE test_runs ADD INDEX idx_status (status) TYPE set(3) GRANULARITY 1")
  end

  def down do
    execute("ALTER TABLE test_runs DROP INDEX idx_status")

    alter table(:test_runs) do
      modify :status, :"Enum8('success' = 0, 'failure' = 1)"
    end

    execute("ALTER TABLE test_runs ADD INDEX idx_status (status) TYPE set(2) GRANULARITY 1")
  end
end
