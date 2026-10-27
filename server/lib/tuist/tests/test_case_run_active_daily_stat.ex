defmodule Tuist.Tests.TestCaseRunActiveDailyStat do
  @moduledoc """
  Ecto schema for the `test_case_runs_active_daily_stats` ClickHouse
  materialized view.

  Stores exact daily presence rows keyed by (project_id, date, is_ci,
  test_case_id) so the Test Cases analytics chart can answer "how many
  distinct test cases ran in the last 14 days?" without merging large exact
  aggregate-state blobs or scanning the source `test_case_runs` table.
  """

  use Ecto.Schema

  @primary_key false
  schema "test_case_runs_active_daily_stats" do
    field :project_id, Ch, type: "Int64"
    field :date, :date
    field :is_ci, :boolean
    field :test_case_id, Ecto.UUID
  end
end
