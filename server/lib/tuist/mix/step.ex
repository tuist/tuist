defmodule Tuist.Mix.Step do
  @moduledoc """
  Work a Mix build did besides compiling files: type checking a module,
  writing modules to disk, running another Mix compiler. Offsets are
  milliseconds from the start of the compile.
  """
  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  @primary_key false
  schema "mix_build_steps" do
    field :id, Ch, type: "UUID"
    field :build_id, Ch, type: "UUID"
    field :project_id, Ch, type: "Int64"
    field :category, Ch, type: "LowCardinality(String)"
    field :title, Ch, type: "String"
    field :path, Ch, type: "String"
    field :start_offset_ms, Ch, type: "UInt32"
    field :duration_ms, Ch, type: "UInt32"
    field :inserted_at, Ch, type: "DateTime"
  end
end
