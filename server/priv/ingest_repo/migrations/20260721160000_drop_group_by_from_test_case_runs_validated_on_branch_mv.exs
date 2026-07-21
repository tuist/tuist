defmodule Tuist.IngestRepo.Migrations.DropGroupByFromTestCaseRunsValidatedOnBranchMv do
  @moduledoc """
  Removes the `GROUP BY` from `test_case_runs_validated_on_branch_mv`.

  The view's only job is to mark each `(project_id, git_branch, test_case_id)`
  that has had a successful, non-flaky run. It was written with a
  `GROUP BY project_id, git_branch, test_case_id`, which makes ClickHouse build
  an `AggregatingTransform` over *every* insert block pushed into
  `test_case_runs` — on the write path, synchronously, for every producer.

  That aggregation state is what exhausted the server's `(total)` memory limit
  under concurrent xcresult processing:

      Code: 241. (total) memory limit exceeded: would use 18.00 GiB,
      maximum: 18.00 GiB. OvercommitTracker decision: Query was selected to
      stop by OvercommitTracker: While executing AggregatingTransform:
      while pushing to view default.test_case_runs_validated_on_branch_mv

  Because the ceiling hit was `(total)` rather than per-query, OvercommitTracker
  killed whichever query it picked next, so the blast radius reached inserts
  that had nothing to do with this view.

  The `GROUP BY` was never load-bearing. The target table is a
  `ReplacingMergeTree` ordered by exactly those three columns, so duplicates
  collapse on merge, and the read path
  (`Tests.test_case_ids_with_successful_default_branch_run/3`) already applies
  `distinct` to tolerate rows that have not merged yet. Dropping it turns the
  per-insert aggregation into a plain projection.

  Only the view is replaced; `test_case_runs_validated_on_branch` keeps its
  data. Between the `DROP` and the `CREATE` a concurrent insert into
  `test_case_runs` would not produce marker rows. A missing marker only makes
  the flaky-test quarantine check treat a case as unvalidated, which is the
  conservative direction, and the marker reappears the next time that case runs
  on the default branch.
  """
  use Ecto.Migration

  alias Tuist.IngestRepo

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_runs_validated_on_branch_mv")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_runs_validated_on_branch_mv
    TO test_case_runs_validated_on_branch
    AS SELECT
      project_id,
      git_branch,
      assumeNotNull(test_case_id) AS test_case_id
    FROM test_case_runs
    WHERE test_case_id IS NOT NULL AND status = 'success' AND is_flaky = false
    """)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_runs_validated_on_branch_mv")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_runs_validated_on_branch_mv
    TO test_case_runs_validated_on_branch
    AS SELECT
      project_id,
      git_branch,
      assumeNotNull(test_case_id) AS test_case_id
    FROM test_case_runs
    WHERE test_case_id IS NOT NULL AND status = 'success' AND is_flaky = false
    GROUP BY project_id, git_branch, test_case_id
    """)
  end
end
