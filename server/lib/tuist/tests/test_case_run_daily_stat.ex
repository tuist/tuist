defmodule Tuist.Tests.TestCaseRunDailyStat do
  @moduledoc false

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
