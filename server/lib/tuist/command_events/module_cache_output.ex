defmodule Tuist.CommandEvents.ModuleCacheOutput do
  @moduledoc """
  A module cache output represents a single module (binary) cache download/upload
  operation performed during a command run.

  It mirrors `Tuist.Builds.CASOutput` (the compilation cache) so module cache
  network analytics reuse the same transfer/latency/throughput surface, but it is
  keyed by `command_event_id` rather than `build_run_id`: module cache artifacts
  are fetched during `tuist generate`, before any build run exists.
  """
  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  @primary_key false
  schema "module_cache_outputs" do
    field :command_event_id, Ch, type: "UUID"
    field :project_id, Ch, type: "Int64"
    field :operation, Ch, type: "Enum8('download' = 0, 'upload' = 1)"
    field :name, Ch, type: "String"
    field :hash, Ch, type: "String"
    field :size, Ch, type: "UInt64"
    field :compressed_size, Ch, type: "UInt64"
    field :duration, Ch, type: "UInt64"
    field :inserted_at, Ch, type: "DateTime"
  end

  def changeset(command_event_id, project_id, attrs) do
    %__MODULE__{}
    |> Ecto.Changeset.cast(
      %{
        command_event_id: command_event_id,
        project_id: project_id,
        operation: attrs[:operation] && to_string(attrs[:operation]),
        name: attrs[:name],
        hash: attrs[:hash],
        size: attrs[:size],
        compressed_size: attrs[:compressed_size],
        duration: attrs[:duration] && trunc(attrs[:duration]),
        inserted_at: :second |> DateTime.utc_now() |> DateTime.to_naive()
      },
      [
        :command_event_id,
        :project_id,
        :operation,
        :name,
        :hash,
        :size,
        :compressed_size,
        :duration,
        :inserted_at
      ]
    )
    |> Ecto.Changeset.validate_required([
      :command_event_id,
      :project_id,
      :operation,
      :name,
      :hash,
      :size,
      :compressed_size,
      :duration
    ])
    |> Ecto.Changeset.validate_inclusion(:operation, ["download", "upload"])
  end
end
