defmodule Tuist.IngestRepo.Migrations.AddXcodeCoverage do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    alter table(:test_runs) do
      add :coverage_covered_lines, :UInt32, default: 0
      add :coverage_executable_lines, :UInt32, default: 0
      add :coverage_observed_covered_lines, :UInt32, default: 0
      add :coverage_observed_executable_lines, :UInt32, default: 0
      add :coverage_carried_forward_files, :UInt32, default: 0
    end

    # Ordered by project and path because a partial run looks earlier evidence up by path
    # across the project's runs; a run's own rows are found through the skipping index.
    execute("""
    CREATE TABLE IF NOT EXISTS xcode_coverage_files
    (
      `id` UUID,
      `test_run_id` UUID,
      `project_id` Int64,
      `path` String,
      `git_blob_id` String,
      `targets` Array(LowCardinality(String)),
      `source` LowCardinality(String),
      `source_test_run_id` Nullable(UUID),
      `covered_lines` UInt32,
      `executable_lines` UInt32,
      `line_numbers` Array(UInt32) CODEC(Delta, ZSTD(1)),
      `execution_counts` Array(UInt64) CODEC(ZSTD(1)),
      `function_names` Array(String),
      `function_line_numbers` Array(UInt32),
      `function_execution_counts` Array(UInt64),
      `function_covered_lines` Array(UInt32),
      `function_executable_lines` Array(UInt32),
      `inserted_at` DateTime64(6) DEFAULT now(),
      INDEX idx_test_run_id test_run_id TYPE bloom_filter GRANULARITY 1
    )
    ENGINE = MergeTree()
    PARTITION BY toYYYYMM(inserted_at)
    ORDER BY (project_id, path, inserted_at)
    """)
  end

  def down do
    drop table(:xcode_coverage_files)

    alter table(:test_runs) do
      remove :coverage_covered_lines
      remove :coverage_executable_lines
      remove :coverage_observed_covered_lines
      remove :coverage_observed_executable_lines
      remove :coverage_carried_forward_files
    end
  end
end
