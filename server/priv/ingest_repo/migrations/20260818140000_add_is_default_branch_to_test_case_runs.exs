defmodule Tuist.IngestRepo.Migrations.AddIsDefaultBranchToTestCaseRuns do
  @moduledoc """
  Denormalizes "did this run happen on the project's default branch" onto the
  run row.

  `test_case_runs` already carries `git_branch`, but the name of a project's
  default branch lives in Postgres. The aggregates over this table are
  ClickHouse materialized views, which cannot reach across to resolve it, so a
  view that wants to key on the default branch needs the answer already on the
  row. `Tuist.Tests.create_test_modules/4` computes it at ingestion, where the
  project is loaded anyway to decide `is_new`, and the flaky-correction
  reinsert carries the original row's value forward so a corrected run keeps
  the classification it was written with.

  The aggregates keyed on this column ship in the same release, which leaves one
  gap worth naming. Managed migrations complete before workload pods roll, so
  between the moment those views are created and the moment the last pod of the
  previous release terminates, runs are still being written by code that does not
  set this column and ClickHouse fills it with the `false` default. Those runs are
  seen by the views and filtered straight back out, and nothing revisits them.

  The gap is one pod rollout wide and it closes on its own. The aggregates are
  only ever read over a trailing window — a calendar window for `last_days`
  alerts, the latest N runs for `rolling` ones — so the affected rows stop being
  read once the window has moved past them. Until then a default-branch figure
  is short by whatever was ingested during the rollout.

  Closing it properly is not available inside one release: any view keyed on a
  column the outgoing pods do not write has this window, whatever order the
  objects are created in. Splitting the column and its readers across two
  releases removes it, at the cost of shipping a dead column and waiting for a
  deploy before any of this is usable.

  Existing rows keep the column default of `false`, and nothing backfills them.
  The aggregate that will consume this covers history by comparing `git_branch`
  against the branch name read from Postgres, so it never needs the column to
  have been right in the past. Rewriting a multi-billion-row fact table to
  answer a question its own backfill can answer from a string comparison would
  be all cost and no gain.
  """
  use Ecto.Migration

  alias Tuist.IngestRepo

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!(
      "ALTER TABLE test_case_runs ADD COLUMN IF NOT EXISTS is_default_branch Bool DEFAULT false"
    )
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("ALTER TABLE test_case_runs DROP COLUMN IF EXISTS is_default_branch")
  end
end
