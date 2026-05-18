defmodule Tuist.Tests.FlakyTestCaseRun do
  @moduledoc """
  Read-only schema backed by the `flaky_test_case_runs` materialized view.
  Stores only flaky test case runs, ordered by (project_id, ran_at, test_case_id).

  Used by:
  - `clear_stale_flaky_flags` / `clear_cooled_down_flaky_tests` for cooldown checks
  - Flaky test cases listing page for aggregated stats with time/environment filters
  """
  use Ecto.Schema

  @primary_key false
  schema "flaky_test_case_runs" do
    field :project_id, Ch, type: "Int64"
    field :test_case_id, Ecto.UUID
    field :test_run_id, Ecto.UUID
    field :inserted_at, Ch, type: "DateTime64(6)"
    field :ran_at, Ch, type: "DateTime64(6)"
    field :is_ci, :boolean
  end
end
