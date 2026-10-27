defmodule Tuist.IngestRepo.Migrations.AddIdProjectionToTestRuns do
  @moduledoc """
  Adds a `proj_by_id` projection to `test_runs` so single-row lookups by
  `id` (e.g. `Tuist.Tests.get_test/2`) binary-search to a single granule
  instead of scanning the table.

  `test_runs` is `ORDER BY (project_id, id)`, so `WHERE id = ?` without
  `project_id` cannot use the primary key. The projection is ordered by
  `id` alone, giving point lookups roughly the cost of one granule read.

  Mirrors `proj_by_id` on `test_case_runs`. Materialization happens in the
  follow-up migration so the metadata change can propagate before the
  slower part rewrite runs.
  """
  use Ecto.Migration

  def up do
    # ReplacingMergeTree rejects ADD PROJECTION unless the table opts into
    # rebuilding projections during deduplicating merges.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_runs
    MODIFY SETTING deduplicate_merge_projection_mode = 'rebuild'
    """

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_runs
    ADD PROJECTION IF NOT EXISTS proj_by_id (
      SELECT *
      ORDER BY id
    )
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_runs DROP PROJECTION IF EXISTS proj_by_id"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_runs
    MODIFY SETTING deduplicate_merge_projection_mode = 'throw'
    """
  end
end
