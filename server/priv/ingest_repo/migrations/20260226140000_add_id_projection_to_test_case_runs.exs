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

  The projection is dropped first (IF EXISTS) to recover from a previous
  partial failure, then re-added. Both DDL statements use `alter_sync = 2`
  to wait for all replicas to acknowledge the metadata change.
  MATERIALIZE is handled in a separate migration to avoid the
  NO_SUCH_PROJECTION_IN_TABLE error that occurs when MATERIALIZE runs
  before the ADD metadata has propagated across replicas.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs DROP PROJECTION IF EXISTS proj_by_id SETTINGS alter_sync = 2"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_case_runs
    ADD PROJECTION proj_by_id (
      SELECT *
      ORDER BY id
    )
    SETTINGS alter_sync = 2
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs DROP PROJECTION IF EXISTS proj_by_id"
  end
end
