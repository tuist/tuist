defmodule Tuist.Cargo.Compilation do
  @moduledoc "One observed rustc invocation, not a per-file compile profile."
  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  @primary_key false
  schema "cargo_compilations" do
    field :id, Ch, type: "UUID"
    field :build_id, Ch, type: "UUID"
    field :project_id, Ch, type: "Int64"
    field :name, Ch, type: "String"
    field :source, Ch, type: "String"
    field :kind, Ch, type: "String"
    field :dependencies, {:array, Ch}, type: "String", default: []
    field :start_offset_ms, Ch, type: "UInt32"
    field :duration_ms, Ch, type: "UInt32"
    field :status, Ch, type: "Enum8('success' = 0, 'failure' = 1)"
    field :diagnostics, Ch, type: "String"
    field :inserted_at, Ch, type: "DateTime"
  end
end
