defmodule Tuist.IngestRepo.Migrations.AddTrackedFilesToTestImpactRuns do
  @moduledoc """
  `tracked_files` on `test_impact_runs`: the patterns the project configured
  for the run on top of its build system's defaults, a change to a file one
  matches falling back to every test (a `!` pattern excludes). And
  `matched_pattern`: the pattern the fallback's `matched_path` matched,
  a default when `tracked_files` doesn't hold it.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "ALTER TABLE test_impact_runs ADD COLUMN IF NOT EXISTS tracked_files Array(String) DEFAULT []"
    )

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "ALTER TABLE test_impact_runs ADD COLUMN IF NOT EXISTS matched_pattern String DEFAULT ''"
    )
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("ALTER TABLE test_impact_runs DROP COLUMN IF EXISTS matched_pattern")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("ALTER TABLE test_impact_runs DROP COLUMN IF EXISTS tracked_files")
  end
end
