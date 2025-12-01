defmodule Tuist.IngestRepo.Migrations.CreateTestCaseFailures do
  use Ecto.Migration

  def up do
    create table(:test_case_failures,
             primary_key: false,
             engine: "MergeTree",
             options:
               "PARTITION BY toYYYYMM(inserted_at) ORDER BY (test_case_run_id, inserted_at, id)"
           ) do
      add :id, :uuid, null: false
      add :test_case_run_id, :uuid, null: false
      add :message, :text
      add :path, :string
      add :line_number, :Int32, null: false
      add :issue_type, :"LowCardinality(String)"
      add :inserted_at, :"DateTime64(6)", default: fragment("now()")
    end

    # Add secondary indices for common query patterns
    execute(
      "ALTER TABLE test_case_failures ADD INDEX idx_test_case_run_id (test_case_run_id) TYPE bloom_filter GRANULARITY 4"
    )

    execute(
      "ALTER TABLE test_case_failures ADD INDEX idx_line_number (line_number) TYPE minmax GRANULARITY 4"
    )
  end

  def down do
    drop table(:test_case_failures)
  end
end
