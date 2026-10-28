defmodule Tuist.Tests.TestImpactChangedFile do
  @moduledoc """
  A path that changed between a test impact's baseline and its commit:
  `status` (`added`, `modified` or `deleted`), `kind` (`source`, `test`,
  `resource`, `tracked` or `ignored`) and how many tests it reaches. This is
  a ClickHouse entity.
  """
  use Ecto.Schema

  @primary_key false
  schema "test_impact_changed_files" do
    field :project_id, Ch, type: "Int64"
    field :head_sha, Ch, type: "String"
    field :baseline_sha, Ch, type: "String"
    field :path, Ch, type: "String"
    field :status, Ch, type: "LowCardinality(String)"
    field :kind, Ch, type: "LowCardinality(String)"
    field :impacted_tests_count, Ch, type: "UInt32"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end
end
