defmodule Tuist.Tests.TestCaseDurationDailyStatsPerCase do
  @moduledoc """
  Ecto schema for the `test_case_duration_daily_stats_per_case` ClickHouse table.

  AggregatingMergeTree keyed on `(project_id, date, test_case_id, is_ci)` with
  aggregate states for the duration of every run of a test case on a day in one
  environment: `run_count`, `avg_duration`, and `p50_duration` / `p90_duration`
  / `p99_duration`.

  The Test Cases listing reads it to show and sort by a duration statistic that
  is bounded to the listing's active window and scoped to the selected
  environment, instead of the unbounded rolling mean denormalized on
  `test_cases.avg_duration`.

  Only the dimension columns are declared here. The aggregate state columns are
  accessed through `fragment()` (`countMerge` / `avgMerge` / `quantileMerge`) in
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
