defmodule Tuist.Bazel.InvocationLog do
  @moduledoc false
  use Ecto.Schema

  @derive {
    Flop.Schema,
    filterable: [:project_id, :invocation_id, :stream, :sequence_number],
    sortable: [:sequence_number, :observed_at, :inserted_at],
    default_order: %{order_by: [:sequence_number], order_directions: [:asc]}
  }

  @primary_key false
  schema "bazel_invocation_logs" do
    field :id, Ch, type: "UUID"
    field :invocation_id, Ch, type: "String"
    field :sequence_number, Ch, type: "UInt64"
    field :stream, Ch, type: "LowCardinality(String)"
    field :message, Ch, type: "String"
    field :project_id, Ch, type: "Int64"
    field :observed_at, Ch, type: "DateTime"
    field :inserted_at, Ch, type: "DateTime"
  end
end
