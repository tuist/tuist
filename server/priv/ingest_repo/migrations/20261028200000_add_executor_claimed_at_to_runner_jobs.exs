defmodule Tuist.IngestRepo.Migrations.AddExecutorClaimedAtToRunnerJobs do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  # When the runner GitHub ran the job on was claimed. Queue time reads it
  # in place of `claimed_at`, which moves with the job between claims. NULL
  # until GitHub names the runner, and on rows written before this column.
  def up do
    # ClickHouse adds a defaulted column without rewriting existing parts.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    ALTER TABLE runner_jobs
      ADD COLUMN IF NOT EXISTS executor_claimed_at Nullable(DateTime64(6, 'UTC')) DEFAULT NULL
    """)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("ALTER TABLE runner_jobs DROP COLUMN IF EXISTS executor_claimed_at")
  end
end
