defmodule Tuist.Bazel.Invocation do
  @moduledoc false
  use Ecto.Schema

  @derive {
    Flop.Schema,
    filterable: [:project_id, :status, :command, :inserted_at],
    sortable: [:inserted_at, :started_at, :finished_at, :duration_ms],
    default_order: %{order_by: [:finished_at], order_directions: [:desc]}
  }

  @primary_key false
  schema "bazel_invocations" do
    field :id, Ch, type: "UUID"
    field :invocation_id, Ch, type: "String"
    field :command, Ch, type: "LowCardinality(String)"
    field :status, Ch, type: "Enum8('success' = 0, 'failure' = 1)"
    field :exit_code, Ch, type: "Int32"
    field :started_at, Ch, type: "DateTime"
    field :finished_at, Ch, type: "DateTime"
    field :duration_ms, Ch, type: "UInt64"
    field :project_id, Ch, type: "Int64"
    field :account_handle, Ch, type: "String"
    field :project_handle, Ch, type: "String"
    field :cache_endpoint, Ch, type: "LowCardinality(String)"
    field :inserted_at, Ch, type: "DateTime"
  end
end
