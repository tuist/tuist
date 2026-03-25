defmodule Tuist.Tests.TestCaseRunByShardId do
  @moduledoc """
  Read-only schema backed by the `test_case_runs_by_shard_id` materialized
  view. Ordered by `(shard_id, name, id)` for efficient filtering, sorting,
  and pagination of sharded test runs.

  Only rows with non-null shard_id are stored.
  For full row data, look up the returned IDs in the main `test_case_runs` table.
  """
  use Ecto.Schema

  @derive {
    Flop.Schema,
    filterable: [:shard_id, :name, :status, :is_flaky, :is_new, :duration, :shard_index], sortable: [:name, :duration]
  }

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "test_case_runs_by_shard_id" do
    field :shard_id, Ecto.UUID
    field :name, Ch, type: "String"
    field :status, Ch, type: "Enum8('success' = 0, 'failure' = 1, 'skipped' = 2)"
    field :is_flaky, :boolean, default: false
    field :is_new, :boolean, default: false
    field :duration, Ch, type: "Int32"
    field :shard_index, Ch, type: "Nullable(Int32)"
  end
end
