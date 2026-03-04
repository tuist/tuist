defmodule Tuist.Tests.TestCaseRunDailyAggregate do
  @moduledoc """
  Ecto schema for the `test_case_runs_daily_stats` ClickHouse materialized view.

  This AggregatingMergeTree MV pre-computes daily aggregates of test case runs
  per (project_id, date, status, is_ci, is_flaky). Analytics queries use
  `-Merge` combinators (countMerge, avgMerge, quantileMerge) via fragments to
  combine these pre-aggregated states instead of scanning millions of raw rows.

  Only the dimension columns are declared here. The aggregate state columns
  (count_state, avg_duration_state, p50/p90/p99_duration_state) are accessed
  through `fragment()` in queries since Ecto has no type mapping for
  ClickHouse's AggregateFunction types.
  """

  use Ecto.Schema

  @primary_key false
  schema "test_case_runs_daily_stats" do
    field :project_id, Ch, type: "Int64"
    field :date, :date
    field :status, Ch, type: "Enum8('success' = 0, 'failure' = 1, 'skipped' = 2)"
    field :is_ci, :boolean
    field :is_flaky, :boolean
  end
end
