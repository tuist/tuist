defmodule Tuist.Tests.XcodeCoverageRun do
  @moduledoc """
  A test run's line coverage totals, merged across its shards, for the
  coverage trend. Every shard report inserts the totals it computed over the
  shards reported so far. Reports can land in any order, so `version` ranks a
  computation by how many shards it included, then by the newest report it
  saw: the most complete one wins.
  """
  use Ecto.Schema

  @primary_key false
  schema "xcode_coverage_runs" do
    field :project_id, Ch, type: "Int64"
    field :test_run_id, Ecto.UUID
    field :covered_lines, Ch, type: "UInt64"
    field :executable_lines, Ch, type: "UInt64"
    field :partial, :boolean, default: false
    field :version, Ch, type: "UInt64"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end
end
