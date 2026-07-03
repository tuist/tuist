defmodule Tuist.IngestRepo.Migrations.CreateTestCaseRunsValidatedOnBranchMv do
  @moduledoc """
  Per-`(project, branch, test_case)` "validated on this branch" marker.

  `AlertEvaluationWorker.reject_unvalidated_test_cases/2` filters a flaky
  alert's triggered test cases down to those with at least one successful,
  non-flaky run on the project's default branch, via
  `Tests.test_case_ids_with_successful_default_branch_run/3`. That check used to
  scan raw `test_case_runs` for the whole triggered set on every evaluation —
  the single most CPU-expensive ClickHouse query on busy projects (multi-second
  raw-table scans reading millions of rows per evaluation).

  This collapses each `(project_id, git_branch, test_case_id)` that has a
  successful, non-flaky run into one marker row in a ReplacingMergeTree keyed
  the same way, so the validation check becomes a bounded primary-key point
  lookup. The MV pre-applies the `status = 'success' AND is_flaky = false`
  filter, so the read only needs `project_id`, `git_branch`, and the
  `test_case_id IN (...)` set.

  Backfill is intentionally NOT run inside this migration: `test_case_runs` is
  a multi-billion-row fact table, and a synchronous partition scan blocks the
  deploy's migration hook past its timeout. The MV forward-fills every new run,
  so the marker table converges as tests run on the default branch. Historical
  rows are backfilled out-of-band (a throttled partition-chunked INSERT run
  after deploy, off the critical path). Until a given test case runs again on
  the default branch it may be treated as "unvalidated" — which only makes
  automated quarantine *more* conservative, never less.
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
    CREATE TABLE IF NOT EXISTS test_case_runs_validated_on_branch (
      project_id Int64,
      git_branch String,
      test_case_id UUID
    ) ENGINE = ReplacingMergeTree
    ORDER BY (project_id, git_branch, test_case_id)
    """)

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

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_runs_validated_on_branch_mv")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP TABLE IF EXISTS test_case_runs_validated_on_branch")
  end
end
