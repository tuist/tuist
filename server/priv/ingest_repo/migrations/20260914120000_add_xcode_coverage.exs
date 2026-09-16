defmodule Tuist.IngestRepo.Migrations.AddXcodeCoverage do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # A report's rows share `inserted_at`, and a shard's retry replaces its earlier
    # report under the same key.
    execute("""
    CREATE TABLE IF NOT EXISTS xcode_coverage_files
    (
      `id` UUID,
      `test_run_id` UUID,
      `project_id` Int64,
      `shard_index` UInt32 DEFAULT 0,
      `partial` Bool DEFAULT false,
      `path` String,
      `git_blob_id` String,
      `targets` Array(LowCardinality(String)),
      `is_test` Bool DEFAULT false,
      `covered_lines` UInt32,
      `executable_lines` UInt32,
      `line_numbers` Array(UInt32) CODEC(Delta, ZSTD(1)),
      `execution_counts` Array(UInt64) CODEC(ZSTD(1)),
      `function_names` Array(String),
      `function_line_numbers` Array(UInt32),
      `function_execution_counts` Array(UInt64),
      `function_covered_lines` Array(UInt32),
      `function_executable_lines` Array(UInt32),
      `inserted_at` DateTime64(6) DEFAULT now()
    )
    ENGINE = ReplacingMergeTree(inserted_at)
    PARTITION BY toYYYYMM(inserted_at)
    ORDER BY (project_id, test_run_id, shard_index, path)
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS xcode_coverage_runs
    (
      `project_id` Int64,
      `test_run_id` UUID,
      `covered_lines` UInt64,
      `executable_lines` UInt64,
      `partial` Bool DEFAULT false,
      `version` UInt64,
      `inserted_at` DateTime64(6) DEFAULT now()
    )
    ENGINE = ReplacingMergeTree(version)
    ORDER BY (project_id, test_run_id)
    """)
  end

  def down do
    drop table(:xcode_coverage_runs)
    drop table(:xcode_coverage_files)
  end
end
