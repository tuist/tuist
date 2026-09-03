defmodule Tuist.IngestRepo.Migrations.CreateTestRunStressRepetitions do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute("""
    CREATE TABLE IF NOT EXISTS test_run_stress_repetitions
    (
      `id` UUID,
      `test_run_id` UUID,
      `project_id` Int64,
      `test_case_id` UUID,
      `repetition_number` UInt16,
      `status` LowCardinality(String),
      `duration` Int32 DEFAULT 0,
      `failure_message` String DEFAULT '',
      `failure_path` String DEFAULT '',
      `failure_line_number` Int32 DEFAULT 0,
      `failure_issue_type` LowCardinality(String) DEFAULT '',
      `inserted_at` DateTime64(6) DEFAULT now()
    )
    ENGINE = MergeTree()
    PARTITION BY toYYYYMM(inserted_at)
    ORDER BY (test_run_id, test_case_id, repetition_number)
    """)
  end

  def down do
    drop table(:test_run_stress_repetitions)
  end
end
