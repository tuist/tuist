defmodule Tuist.TestImpactAnalysis.RunTest do
  @moduledoc """
  A test an impact run selected, with the rule that selected it (`reason`)
  and, for `impacted`, the first path whose blob differs (`matched_path`). The
  module, suite and name are copied from the test case, so a shard reads its
  suites by prefix and the client builds identifiers without a join. They
  record intent; `test_case_runs` records the outcome. This is a ClickHouse
  entity.
  """
  use Ecto.Schema

  @primary_key false
  schema "test_impact_run_tests" do
    field :test_impact_run_id, Ecto.UUID
    field :project_id, Ch, type: "Int64"
    field :test_case_id, Ecto.UUID
    field :module_name, Ch, type: "String"
    field :suite_name, Ch, type: "String", default: ""
    field :name, Ch, type: "String"
    field :reason, Ch, type: "LowCardinality(String)"
    field :matched_path, Ch, type: "String", default: ""
    field :inserted_at, Ch, type: "DateTime64(6)"
  end
end
