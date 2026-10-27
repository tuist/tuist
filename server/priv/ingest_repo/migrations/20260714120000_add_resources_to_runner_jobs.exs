defmodule Tuist.IngestRepo.Migrations.AddResourcesToRunnerJobs do
  use Ecto.Migration

  def up do
    # ClickHouse adds these metadata-only columns without rewriting existing parts.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    ALTER TABLE runner_jobs
      ADD COLUMN IF NOT EXISTS platform LowCardinality(String) DEFAULT '',
      ADD COLUMN IF NOT EXISTS vcpus Int32 DEFAULT 0,
      ADD COLUMN IF NOT EXISTS memory_gb Int32 DEFAULT 0
    """)
  end

  def down do
    # The columns are derived runner-shape metadata and safe to remove on rollback.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    ALTER TABLE runner_jobs
      DROP COLUMN IF EXISTS platform,
      DROP COLUMN IF EXISTS vcpus,
      DROP COLUMN IF EXISTS memory_gb
    """)
  end
end
