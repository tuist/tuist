defmodule Tuist.Tests.TestExecution do
  @moduledoc """
  One ingested report or shard execution, shared by its case runs and destinations.

  A merged test run can contain multiple executions with different destinations.
  Destination status distinguishes missing metadata from a single attributable
  destination and incomplete or multiple destinations. Immutable report replays
  reuse the execution ID; legacy reports receive a new ID on ingestion.
  """
  use Ecto.Schema

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "test_executions" do
    field :project_id, Ch, type: "Int64"
    field :test_run_id, Ecto.UUID
    field :git_commit_sha, Ch, type: "String"
    field :scheme, Ch, type: "String"
    field :is_ci, :boolean, default: false
    field :shard_id, Ch, type: "Nullable(UUID)"
    field :shard_index, Ch, type: "Nullable(Int32)"
    field :destination_status, Ch, type: "Enum8('missing' = 0, 'single' = 1, 'ambiguous' = 2)"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end
end
