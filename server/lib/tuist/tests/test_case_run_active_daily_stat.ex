defmodule Tuist.Tests.TestCaseRunActiveDailyStat do
  @moduledoc """
  Ecto schema for the `test_case_runs_active_daily_stats` ClickHouse
  materialized view.

  Stores `uniqExactState(test_case_id)` per (project_id, date, is_ci) so the
  Test Cases analytics chart can answer "how many distinct test cases ran in
  the last 14 days?" by merging at most ~28 daily states instead of scanning
  the source `test_case_runs` table.

  The aggregate state column (`test_case_ids_state`) is accessed through
  `fragment("uniqExactMerge(test_case_ids_state)")` because Ecto has no type
  mapping for ClickHouse's `AggregateFunction` types.
  """

  use Ecto.Schema

  @primary_key false
  schema "test_case_runs_active_daily_stats" do
    field :project_id, Ch, type: "Int64"
    field :date, :date
    field :is_ci, :boolean
  end
end
