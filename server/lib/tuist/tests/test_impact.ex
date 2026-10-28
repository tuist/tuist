defmodule Tuist.Tests.TestImpact do
  @moduledoc """
  What changed between a commit (`head_sha`) and its baseline
  (`baseline_sha`, the nearest ancestor whose full run recorded per-test
  coverage evidence), and how many tests that change reaches. Deterministic
  for the pair, so every selection run on the commit against that baseline
  reuses it. This is a ClickHouse entity.
  """
  use Ecto.Schema

  @primary_key false
  schema "test_impacts" do
    field :project_id, Ch, type: "Int64"
    field :head_sha, Ch, type: "String"
    field :baseline_sha, Ch, type: "String"
    field :git_branch, Ch, type: "String"
    field :changed_files_count, Ch, type: "UInt32"
    field :impacted_tests_count, Ch, type: "UInt32"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end
end
