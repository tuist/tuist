defmodule Tuist.IngestRepo.Migrations.CreateTestCasesLastRanByCiMv do
  @moduledoc """
  Pre-aggregated view of "when did each test case last run, scoped by CI vs.
  local" so the Test Cases listing's CI/Local filter can resolve its active
  set without scanning `test_case_runs`.

  The dashboard's `is_ci: true | false` path previously joined
  `test_case_runs` to compute `WHERE test_case_id IN (… active in window …)`
  — production traces showed ~94 M rows / ~4 GB read for a single project
  query (project 1227, 30-day window). The `proj_by_branch_ci` projection
  doesn't help here because it requires a `git_branch` filter that the
  listing doesn't supply.

  This `AggregatingMergeTree` keeps one `(project_id, is_ci, test_case_id)`
  tuple per `maxState(ran_at)`, bounded in size by `2 × distinct test cases
  per project`. Active-set lookups become a tiny `GROUP BY` on the MV with
  `HAVING maxMerge(...) BETWEEN ?`.

  `test_case_id` on `test_case_runs` is `Nullable(UUID)`, but AggregatingMergeTree
  rejects nullable sort key columns by default. The cast happens in an inner
  subquery so the outer aggregation sees a plain non-nullable column already
  named `test_case_id` — doing the cast at the outer level instead would
  alias-shadow the source column in WHERE/GROUP BY (ClickHouse resolves
  alias names ahead of column names) and trip a "not under aggregate
  function" error.

  `POPULATE` backfills from existing `test_case_runs` at create time. Inserts
  during the populate window are not captured by ClickHouse's POPULATE
  semantics, so allow for a brief gap immediately after deploy — subsequent
  inserts trigger the MV normally.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    CREATE MATERIALIZED VIEW IF NOT EXISTS test_cases_last_ran_by_ci
    ENGINE = AggregatingMergeTree
    ORDER BY (project_id, is_ci, test_case_id)
    POPULATE
    AS SELECT
      project_id,
      is_ci,
      test_case_id,
      maxState(ran_at) AS last_ran_at_state
    FROM (
      SELECT
        project_id,
        is_ci,
        assumeNotNull(test_case_id) AS test_case_id,
        ran_at
      FROM test_case_runs
      WHERE isNotNull(test_case_id)
    )
    GROUP BY project_id, is_ci, test_case_id
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "DROP VIEW IF EXISTS test_cases_last_ran_by_ci"
  end
end
