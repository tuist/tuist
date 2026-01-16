defmodule Tuist.IngestRepo.Migrations.CreateTestCaseRunRepetitions do
  use Ecto.Migration

  def up do
    create table(:test_case_run_repetitions,
             primary_key: false,
             engine: "MergeTree",
             options:
               "PARTITION BY toYYYYMM(inserted_at) ORDER BY (test_case_run_id, repetition_number, inserted_at)"
           ) do
      add :id, :uuid, null: false
      add :test_case_run_id, :uuid, null: false
      add :repetition_number, :Int32, null: false
      add :name, :string, null: false
      add :status, :"LowCardinality(String)", null: false
      add :duration, :Int32, null: false, default: 0
      add :inserted_at, :"DateTime64(6)", default: fragment("now()")
    end

    execute(
      "ALTER TABLE test_case_run_repetitions ADD INDEX idx_test_case_run_id (test_case_run_id) TYPE bloom_filter GRANULARITY 4"
    )

    execute(
      "ALTER TABLE test_case_run_repetitions ADD INDEX idx_status (status) TYPE set(2) GRANULARITY 1"
    )
  end

  def down do
    drop table(:test_case_run_repetitions)
  end
end
