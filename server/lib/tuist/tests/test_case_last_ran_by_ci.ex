defmodule Tuist.Tests.TestCaseLastRanByCi do
  @moduledoc """
  Ecto schema for the `test_cases_last_ran_by_ci` ClickHouse materialized
  view.

  Stores `maxState(ran_at)` per `(project_id, is_ci, test_case_id)` so the
  Test Cases listing's CI/Local-filtered active-period lookup can resolve
  its set of active `test_case_id`s without scanning `test_case_runs`.

  The aggregate state column (`last_ran_at_state`) is accessed through
  `fragment("maxMerge(last_ran_at_state)")` because Ecto has no type
  mapping for ClickHouse's `AggregateFunction` types.
  """

  use Ecto.Schema

  # `tc_id` is named differently from `test_cases.id` / `test_case_runs.test_case_id`
  # because aliasing the projection back to `test_case_id` in the MV's SELECT
  # collides with the source column name in the GROUP BY (ClickHouse resolves
  # alias names ahead of column names). See the migration for the full reasoning.
  @primary_key false
  schema "test_cases_last_ran_by_ci" do
    field :project_id, Ch, type: "Int64"
    field :is_ci, :boolean
    field :tc_id, Ch, type: "UUID"
  end
end
