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

  This ships ahead of anything that reads it, on purpose. Managed migrations
  complete before workload pods roll, so for the length of a deploy the
  previous release is still writing rows without this column and ClickHouse
  fills them with the `false` default. A materialized view keyed on the column
  in this same release would record those runs as off-default and never revisit
  them. Landing the column and its writer first means the column is already
  being populated correctly by the time a later release builds an aggregate on
  it.

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
