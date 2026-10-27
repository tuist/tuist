defmodule Tuist.Mix.Diagnostic do
  @moduledoc """
  Ecto schema for Mix (Elixir) compile diagnostics stored in ClickHouse.
  """
  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  @primary_key false
  schema "mix_diagnostics" do
    field :id, Ch, type: "UUID"
    field :build_id, Ch, type: "UUID"
    field :project_id, Ch, type: "Int64"
    field :severity, Ch, type: "Enum8('warning' = 0, 'error' = 1)"
    field :file, Ch, type: "String"
    field :module, Ch, type: "String"
    field :message, Ch, type: "String"
    field :line, Ch, type: "Nullable(UInt32)"
    field :column, Ch, type: "Nullable(UInt32)"
    field :compiler, Ch, type: "LowCardinality(String)"
    field :inserted_at, Ch, type: "DateTime"
  end
end
