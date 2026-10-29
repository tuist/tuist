defmodule Tuist.Mix.CompiledFile do
  @moduledoc """
  A file compiled during a Mix build: how long it took, the modules it
  defines, the project files it depends on, and how long it sat paused
  while other files compiled.
  """
  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  @primary_key false
  schema "mix_compiled_files" do
    field :id, Ch, type: "UUID"
    field :build_id, Ch, type: "UUID"
    field :project_id, Ch, type: "Int64"
    field :path, Ch, type: "String"
    field :start_offset_ms, Ch, type: "Nullable(UInt32)"
    field :compile_duration_ms, Ch, type: "UInt32"
    field :wait_duration_ms, Ch, type: "UInt32"
    field :modules, {:array, Ch}, type: "String", default: []
    field :dependency_paths, {:array, Ch}, type: "String", default: []
    field :dependency_kinds, {:array, Ch}, type: "String", default: []
    field :wait_durations_ms, {:array, Ch}, type: "UInt32", default: []
    field :wait_start_offsets_ms, {:array, Ch}, type: "Nullable(UInt32)", default: []
    field :inserted_at, Ch, type: "DateTime"
  end
end
