defmodule Tuist.IngestRepo.Migrations.AddTestCaseIdToTestCaseRuns do
  use Ecto.Migration

  def up do
    alter table(:test_case_runs) do
      add :test_case_id, :"Nullable(UUID)"
    end

    execute(
      "ALTER TABLE test_case_runs ADD INDEX idx_test_case_id (test_case_id) TYPE bloom_filter GRANULARITY 4"
    )
  end

  def down do
    execute("ALTER TABLE test_case_runs DROP INDEX idx_test_case_id")

    alter table(:test_case_runs) do
      remove :test_case_id
    end
  end
end
