defmodule Tuist.Tests.TestCaseRunByTestRun do
  @moduledoc """
  Slim read-only schema backed by the `test_case_runs_by_test_run` table
  (populated by a materialized view). Ordered by `(test_run_id, id)`,
  making queries that filter by `test_run_id` efficient.

  Used for:
  - Aggregation queries (`get_test_run_metrics`, `get_test_run_failures_count`)
  - ID subqueries to pre-filter `list_test_case_runs`
  """
  use Ecto.Schema

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "test_case_runs_by_test_run" do
    field :test_run_id, Ecto.UUID
    field :status, Ch, type: "Enum8('success' = 0, 'failure' = 1, 'skipped' = 2)"
    field :is_flaky, :boolean, default: false
    field :duration, Ch, type: "Int32"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end
end
