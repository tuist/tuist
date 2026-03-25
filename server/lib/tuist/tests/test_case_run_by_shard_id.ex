defmodule Tuist.Tests.TestCaseRunByShardId do
  @moduledoc """
  Minimal read-only schema backed by the `test_case_runs_by_shard_id`
  materialized view. Ordered by `(shard_id, id)` for efficient lookups
  when filtering sharded test runs.
  """
  use Ecto.Schema

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "test_case_runs_by_shard_id" do
    field :shard_id, Ecto.UUID
  end
end
