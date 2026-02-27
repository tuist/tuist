defmodule Tuist.IngestRepo.Migrations.AddIdProjectionToTestCaseRuns do
  @moduledoc """
  Adds and materializes a `proj_by_id` projection to speed up single-row lookups by `id`.

  The table is ordered by `(test_run_id, test_module_run_id, id)`, so a query
  like `WHERE id = ? LIMIT 1` cannot binary-search directly to the row —
  it must scan across all leading-key combinations. The existing bloom filter
  `idx_id` only skips granule groups (it reads ~4.4 M of 5.5 M rows on average).

  A projection ordered by `id` lets ClickHouse binary-search to the exact
  granule, reducing reads from millions of rows to ~1 granule (~8192 rows).
  This optimizes `getTestCaseRun` (the test case run detail page).

  The migration first drops the projection if it exists (to recover from a
  previous partial failure), then combines ADD and MATERIALIZE in a single
  ALTER TABLE statement to avoid the NO_SUCH_PROJECTION_IN_TABLE error that
  occurs when they run as separate statements before the ADD metadata change
  has propagated across replicas.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs DROP PROJECTION IF EXISTS proj_by_id"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_case_runs
      ADD PROJECTION proj_by_id (
        SELECT *
        ORDER BY id
      ),
      MATERIALIZE PROJECTION proj_by_id
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs DROP PROJECTION IF EXISTS proj_by_id"
  end
end
