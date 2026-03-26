defmodule Tuist.Tests.TestCaseRunByTestRun do
  @moduledoc """
  Slim read-only schema backed by the `test_case_runs_by_test_run` materialized
  view. Ordered by `(test_run_id, ran_at, id)`, making queries that filter by
  `test_run_id` efficient.

  Used for:
  - Aggregation queries (`get_test_run_metrics`, `get_test_run_failures_count`)
  - Flop-driven filtering, sorting, and pagination of test case runs scoped to
    a test run — only the ~20 result IDs are then looked up in the main table
  """
  use Ecto.Schema

  @derive {
    Flop.Schema,
    filterable: [:test_run_id, :name, :status, :is_flaky, :is_new, :duration],
    sortable: [:inserted_at, :duration, :name, :ran_at]
  }

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "test_case_runs_by_test_run" do
    field :test_run_id, Ecto.UUID
    field :status, Ch, type: "Enum8('success' = 0, 'failure' = 1, 'skipped' = 2)"
    field :is_flaky, :boolean, default: false
    field :is_new, :boolean, default: false
    field :duration, Ch, type: "Int32"
    field :inserted_at, Ch, type: "DateTime64(6)"
    field :ran_at, Ch, type: "DateTime64(6)"
    field :name, Ch, type: "String"
    field :project_id, Ch, type: "Int64"
  end
end
