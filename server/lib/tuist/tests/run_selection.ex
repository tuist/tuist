defmodule Tuist.Tests.RunSelection do
  @moduledoc """
  How many tests a test run's selection avoided (`Tuist.Tests.RunSelections`).
  This is a ClickHouse entity.
  """
  use Ecto.Schema

  @primary_key false
  schema "test_run_selections" do
    field :project_id, Ch, type: "Int64"
    field :test_run_id, Ch, type: "UUID"
    field :ran_at, Ch, type: "DateTime64(6)"
    field :build_system, Ch, type: "LowCardinality(String)"
    field :is_ci, :boolean, default: false
    field :scheme, Ch, type: "String", default: ""
    field :git_branch, Ch, type: "String", default: ""
    field :strategy, Ch, type: "LowCardinality(String)"
    field :test_impact_run_id, Ch, type: "Nullable(UUID)"
    field :scope_tests, Ch, type: "UInt32", default: 0
    field :avoided_tests, Ch, type: "UInt32", default: 0
    field :estimated_tests, Ch, type: "UInt32", default: 0
    field :avoided_by, Ch, type: "Map(LowCardinality(String), UInt32)", default: %{}
    field :inserted_at, Ch, type: "DateTime64(6)"
  end
end
