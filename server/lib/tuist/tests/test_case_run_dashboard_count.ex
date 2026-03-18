defmodule Tuist.Tests.TestCaseRunDashboardCount do
  @moduledoc """
  Ecto schema for the `test_case_runs_dashboard_count` ClickHouse materialized view.

  This AggregatingMergeTree MV pre-computes daily counts of test case runs by
  is_flaky flag. Dashboard queries use `countMerge(count)` via fragments to
  combine these pre-aggregated states instead of scanning millions of raw rows.

  Only the dimension columns are declared here. The aggregate state column
  (count) is accessed through `fragment()` in queries since Ecto has no type
  mapping for ClickHouse's AggregateFunction types.
  """

  use Ecto.Schema

  @primary_key false
  schema "test_case_runs_dashboard_count" do
    field :day, :date
    field :is_flaky, :boolean
  end
end
