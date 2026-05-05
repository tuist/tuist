defmodule Tuist.IngestRepo.Migrations.AddIdProjectionToTestCaseRuns do
  @moduledoc """
  Adds a `proj_by_id` projection to `test_case_runs` so single-row lookups by
  `id` (e.g. `Tuist.Tests.get_test_case_run_by_id/2` and the cross-run
  flakiness re-fetch in `mark_test_case_runs_as_flaky`) binary-search to a
  single granule instead of scanning every monthly partition.

  The table is `ORDER BY (project_id, test_case_id, ran_at, id)`, so a query
  filtering only by `id` cannot use the primary key — the existing `idx_id`
  bloom filter trims granules but still lets hundreds of millions of rows
  through (a recent alert showed 375M rows scanned to return 19). A
  projection ordered by `id` alone gives point lookups roughly the cost of
  one granule read.

  An earlier `proj_by_id` was dropped when the table was reordered and
  converted to ReplacingMergeTree (see
  `20260319120000_reorder_test_case_runs.exs`); this migration re-adds it
  using the same opt-in (`deduplicate_merge_projection_mode = 'rebuild'`)
  that already works on `build_runs`, `test_runs`, and `test_module_runs`.
  Materialization happens in the follow-up migration so the metadata
  change can propagate before the slower part rewrite runs.
  """
  use Ecto.Migration

  def up do
    # ReplacingMergeTree rejects ADD PROJECTION unless the table opts into
    # rebuilding projections during deduplicating merges.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_case_runs
    MODIFY SETTING deduplicate_merge_projection_mode = 'rebuild'
    """

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_case_runs
    ADD PROJECTION IF NOT EXISTS proj_by_id (
      SELECT *
      ORDER BY id
    )
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs DROP PROJECTION IF EXISTS proj_by_id"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_case_runs
    MODIFY SETTING deduplicate_merge_projection_mode = 'throw'
    """
  end
end
