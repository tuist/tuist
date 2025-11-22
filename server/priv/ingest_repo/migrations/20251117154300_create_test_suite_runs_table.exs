defmodule Tuist.IngestRepo.Migrations.CreateTestSuiteRunsTable do
  use Ecto.Migration

  def up do
    create table(:test_suite_runs,
             primary_key: false,
             engine: "MergeTree",
             options:
               "PARTITION BY toYYYYMM(inserted_at) ORDER BY (test_run_id, test_module_run_id, inserted_at, id)"
           ) do
      add :id, :uuid, null: false
      add :name, :string, null: false
      add :test_run_id, :uuid, null: false
      add :test_module_run_id, :uuid, null: false
      add :status, :"Enum8('success' = 0, 'failure' = 1, 'skipped' = 2)", null: false
      add :duration, :Int32, null: false
      add :test_case_count, :Int32, default: 0
      add :avg_test_case_duration, :Int32, default: 0
      add :inserted_at, :"DateTime64(6)", default: fragment("now()")
    end

    # Add secondary indices for common query patterns
    execute(
      "ALTER TABLE test_suite_runs ADD INDEX idx_test_run_id (test_run_id) TYPE bloom_filter GRANULARITY 4"
    )

    execute(
      "ALTER TABLE test_suite_runs ADD INDEX idx_test_module_run_id (test_module_run_id) TYPE bloom_filter GRANULARITY 4"
    )

    execute("ALTER TABLE test_suite_runs ADD INDEX idx_status (status) TYPE set(3) GRANULARITY 1")

    execute(
      "ALTER TABLE test_suite_runs ADD INDEX idx_duration (duration) TYPE minmax GRANULARITY 4"
    )

    execute(
      "ALTER TABLE test_suite_runs ADD INDEX idx_name (name) TYPE bloom_filter GRANULARITY 4"
    )
  end

  def down do
    drop table(:test_suite_runs)
  end
end
