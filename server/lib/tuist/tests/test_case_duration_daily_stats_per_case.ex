defmodule Tuist.Tests.TestCaseDurationDailyStatsPerCase do
  @moduledoc """
  Ecto schema for the `test_case_duration_daily_stats_per_case` ClickHouse table.

  AggregatingMergeTree keyed on `(project_id, test_case_id, date, is_ci)` with
  aggregate states for the duration of every run of a test case on a day in one
  environment: `run_count`, `avg_duration`, and `p50_duration` / `p90_duration`
  / `p99_duration`.

  The Test Cases listing reads it to show and sort by durations bounded to the
  listing's active window and scoped to the selected environment, instead of the
  unbounded rolling mean denormalized on `test_cases.avg_duration`.

  `run_count` is a `uniqExact` state over run ids, not a plain count: a
  flaky-state correction re-inserts a run and so reaches this table twice, and
  the listing's minimum-sample floor has to be exact. The migration carries the
  full reasoning, including why the value states cannot be made idempotent the
  same way.

  Only the dimension columns are declared here. The aggregate state columns are
  accessed through `fragment()` (`uniqExactMerge` / `avgMerge` / `quantileMerge`) in
  queries since Ecto has no type mapping for ClickHouse `AggregateFunction`
  types.
  """
  use Ecto.Schema

  @primary_key false
  schema "test_case_duration_daily_stats_per_case" do
    field :project_id, Ch, type: "Int64"
    field :date, :date
    field :test_case_id, Ecto.UUID
    field :is_ci, :boolean
  end
end
