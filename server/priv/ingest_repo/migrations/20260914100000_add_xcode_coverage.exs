defmodule Tuist.IngestRepo.Migrations.AddXcodeCoverage do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    alter table(:test_runs) do
      add :coverage_covered_lines, :UInt32, default: 0
      add :coverage_executable_lines, :UInt32, default: 0
    end

    execute("""
    CREATE TABLE IF NOT EXISTS xcode_coverage_files
    (
      `id` UUID,
      `test_run_id` UUID,
      `project_id` Int64,
      `target_name` String,
      `path` String,
      `covered_lines` UInt32,
      `executable_lines` UInt32,
      `inserted_at` DateTime64(6) DEFAULT now()
    )
    ENGINE = MergeTree()
    PARTITION BY toYYYYMM(inserted_at)
    ORDER BY (test_run_id, target_name, path)
    """)
  end

  def down do
    drop table(:xcode_coverage_files)

    alter table(:test_runs) do
      remove :coverage_covered_lines
      remove :coverage_executable_lines
    end
  end
end
