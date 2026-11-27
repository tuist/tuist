defmodule Tuist.IngestRepo.Migrations.AddDirtyFilesToTestImpactRuns do
  @moduledoc """
  `dirty_files` on `test_impact_runs`: the uncommitted changes of a run from
  a dirty checkout, the changed files its client marked `dirty` (path,
  status, blob), so the Selective Testing tab can show them. Such a run falls
  back without a diff, and a dirty diff can't go into `test_impact_diffs`,
  which clean runs of the same commit and baseline reuse. Empty for every
  other run, and for dirty runs of clients that don't mark files.

  Paths keep the file retention (`TUIST_COVERAGE_FILE_RETENTION_DAYS`), as
  stored diffs do, through a column time-to-live, while the run row keeps the
  run retention. Adding a column with a default only changes metadata.
  """
  use Ecto.Migration

  alias Tuist.Environment

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    days = Environment.coverage_retention_days().files

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    ALTER TABLE test_impact_runs ADD COLUMN IF NOT EXISTS dirty_files
      Array(Tuple(String, LowCardinality(String), String)) DEFAULT []
      TTL toDateTime(inserted_at) + INTERVAL #{days} DAY
    """)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("ALTER TABLE test_impact_runs DROP COLUMN IF EXISTS dirty_files")
  end
end
