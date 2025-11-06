defmodule Tuist.Runs.CASOutput do
  @moduledoc """
  A CAS output represents cache upload/download operations for a build run.
  """
  use Ecto.Schema

  @derive {
    Flop.Schema,
    filterable: [:build_run_id, :node_id, :operation], sortable: [:node_id]
  }

  @primary_key false
  schema "cas_outputs" do
    field :node_id, Ch, type: "String"
    field :checksum, Ch, type: "String"
    field :size, Ch, type: "UInt64"
    field :duration, Ch, type: "UInt64"
    field :compressed_size, Ch, type: "UInt64"
    field :operation, Ch, type: "Enum8('download' = 0, 'upload' = 1)"
    field :build_run_id, Ch, type: "UUID"
    field :inserted_at, Ch, type: "DateTime"
  end

  def changeset(build_run_id, attrs) do
    %__MODULE__{}
    |> Ecto.Changeset.cast(
      %{
        build_run_id: build_run_id,
        node_id: attrs[:node_id],
        checksum: attrs[:checksum],
        size: attrs[:size],
        duration: attrs[:duration] && trunc(attrs[:duration] * 1000),
        compressed_size: attrs[:compressed_size],
        operation: attrs[:operation] && to_string(attrs[:operation]),
        inserted_at: :second |> DateTime.utc_now() |> DateTime.to_naive()
      },
      [:build_run_id, :node_id, :checksum, :size, :duration, :compressed_size, :operation, :inserted_at]
    )
    |> Ecto.Changeset.validate_required([:build_run_id, :node_id, :checksum, :size, :duration, :compressed_size, :operation])
  end
end