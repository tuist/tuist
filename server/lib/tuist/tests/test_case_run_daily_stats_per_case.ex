defmodule Tuist.Tests.TestCaseRunDailyStatsPerCase do
  @moduledoc """
  Ecto schema for the `test_case_run_daily_stats_per_case` ClickHouse table.

  AggregatingMergeTree keyed on `(project_id, date, test_case_id)` with two
  aggregate states: `run_count` (count of every run) and `flaky_run_count`
  (sum of `is_flaky` cast to UInt8). The flaky-tests automation engine uses
  it to compute per-test flaky counts and rates over a window with a small
  prefix scan, instead of aggregating against the raw `test_case_runs`
  table.

  Only the dimension columns are declared here. The aggregate state columns
  are accessed through `fragment()` (`countMerge` / `sumMerge`) in queries
  since Ecto has no type mapping for ClickHouse `AggregateFunction` types.
  """
  use Ecto.Schema

  @primary_key false
  schema "test_case_run_daily_stats_per_case" do
    field :project_id, Ch, type: "Int64"
    field :date, :date
    field :test_case_id, Ecto.UUID
  end
end
