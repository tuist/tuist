defmodule Tuist.Tests.CoverageRun do
  @moduledoc """
  A test run's line coverage totals, merged across its shards, for the
  coverage trend, with what measured them: the build system, the coverage
  tool and its version, the repository's Git object format and the scheme
  (the configuration the figures belong to). Every shard report inserts the totals it computed over the
  shards reported so far. Reports can land in any order, so `version` ranks a
  computation by how many shards it included, then by the newest report it
  saw: the most complete one wins. When the project's excluded paths change,
  `Tuist.Tests.Coverage.recompute_totals/2` republishes a run's totals one
  version above the latest, with its original `inserted_at`.
  """
  use Ecto.Schema

  @primary_key false
  schema "coverage_runs" do
    field :project_id, Ch, type: "Int64"
    field :test_run_id, Ecto.UUID
    field :build_system, Ch, type: "LowCardinality(String)", default: "xcode"
    field :coverage_tool, Ch, type: "LowCardinality(String)", default: ""
    field :coverage_tool_version, Ch, type: "LowCardinality(String)", default: ""
    field :git_object_format, Ch, type: "LowCardinality(String)", default: ""
    field :scheme, Ch, type: "String", default: ""
    field :covered_lines, Ch, type: "UInt64"
    field :executable_lines, Ch, type: "UInt64"
    field :partial, :boolean, default: false
    field :version, Ch, type: "UInt64"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end
end
