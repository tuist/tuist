defmodule Tuist.IngestRepo.Migrations.DropTestRunStressRepetitions do
  use Ecto.Migration

  def up do
    execute("DROP TABLE IF EXISTS test_run_stress_repetitions")
  end

  def down do
    execute("""
    CREATE TABLE IF NOT EXISTS test_run_stress_repetitions
    (
      `id` UUID,
      `test_run_id` UUID,
      `project_id` Int64,
      `test_case_id` UUID,
      `repetition_number` UInt16,
      `status` LowCardinality(String),
      `duration` Int32,
      `failure_message` String,
      `failure_path` String,
      `failure_line_number` Int32,
      `failure_issue_type` LowCardinality(String),
      `inserted_at` DateTime64(6) DEFAULT now()
    )
    ENGINE = MergeTree()
    PARTITION BY toYYYYMM(inserted_at)
    ORDER BY (test_run_id, test_case_id, repetition_number, id)
    """)
  end
end
