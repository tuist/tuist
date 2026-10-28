defmodule Tuist.Tests.TestImpactTest do
  @moduledoc """
  A test a test impact reaches, whatever invocation asks for it: `reason`
  (`impacted`, `target_changed` or `failed_at_baseline`) and the changed
  path that matched (`matched_path`, empty for `failed_at_baseline`). This
  is a ClickHouse entity.
  """
  use Ecto.Schema

  @primary_key false
  schema "test_impact_tests" do
    field :project_id, Ch, type: "Int64"
    field :head_sha, Ch, type: "String"
    field :baseline_sha, Ch, type: "String"
    field :test_case_id, Ch, type: "UUID"
    field :module_name, Ch, type: "String"
    field :suite_name, Ch, type: "String"
    field :name, Ch, type: "String"
    field :reason, Ch, type: "LowCardinality(String)"
    field :matched_path, Ch, type: "String"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end
end
