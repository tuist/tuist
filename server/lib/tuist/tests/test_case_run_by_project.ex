defmodule Tuist.Tests.TestCaseRunByProject do
  @moduledoc """
  Slim read-only schema backed by the `test_case_runs_by_project` materialized
  view. Ordered by `(project_id, ran_at, id)`, making queries that filter by
  `project_id` and sort by `ran_at` efficient without scanning the whole
  project on the main table.

  Used by `Tuist.Tests.list_test_case_runs/2` for the project-only filter
  path: filter + sort + paginate run on the MV, then the page-sized set of
  IDs is fetched from the main `test_case_runs` table.
  """
  use Ecto.Schema

  @derive {
    Flop.Schema,
    filterable: [
      :project_id,
      :test_case_id,
      :name,
      :status,
      :is_flaky,
      :is_new,
      :is_ci,
      :is_quarantined,
      :duration,
      :account_id,
      :scheme,
      :git_branch
    ],
    sortable: [:inserted_at, :duration, :name, :ran_at]
  }

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "test_case_runs_by_project" do
    field :project_id, Ch, type: "Int64"
    field :ran_at, Ch, type: "DateTime64(6)"
    field :inserted_at, Ch, type: "DateTime64(6)"
    field :name, Ch, type: "String"
    field :status, Ch, type: "Enum8('success' = 0, 'failure' = 1, 'skipped' = 2)"
    field :is_flaky, :boolean, default: false
    field :is_new, :boolean, default: false
    field :is_ci, :boolean, default: false
    field :is_quarantined, :boolean, default: false
    field :duration, Ch, type: "Int32"
    field :test_case_id, Ch, type: "Nullable(UUID)"
    field :account_id, Ch, type: "Nullable(Int64)"
    field :scheme, Ch, type: "String"
    field :git_branch, Ch, type: "String"
  end
end
