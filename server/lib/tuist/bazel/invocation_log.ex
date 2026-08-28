defmodule Tuist.Bazel.InvocationLog do
  @moduledoc false
  use Ecto.Schema

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
