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
    field :started_at, Ch, type: "DateTime64(3)"
    field :finished_at, Ch, type: "DateTime64(3)"
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
        started_at: parse_datetime(attrs[:started_at]),
        finished_at: parse_datetime(attrs[:finished_at]),
        duration: attrs[:duration] && trunc(attrs[:duration] * 1000),
        compressed_size: attrs[:compressed_size],
        operation: attrs[:operation] && to_string(attrs[:operation]),
        inserted_at: :second |> DateTime.utc_now() |> DateTime.to_naive()
      },
      [:build_run_id, :node_id, :checksum, :size, :started_at, :finished_at, :duration, :compressed_size, :operation, :inserted_at]
    )
    |> Ecto.Changeset.validate_required([:build_run_id, :node_id, :checksum, :size, :started_at, :finished_at, :duration, :compressed_size, :operation])
  end

  defp parse_datetime(nil), do: nil
  defp parse_datetime(%DateTime{} = dt), do: dt |> DateTime.to_naive()
  defp parse_datetime(timestamp) when is_number(timestamp) do
    timestamp
    |> DateTime.from_unix!(:millisecond)
    |> DateTime.to_naive()
  end
  defp parse_datetime(date_string) when is_binary(date_string) do
    case DateTime.from_iso8601(date_string) do
      {:ok, dt, _} -> DateTime.to_naive(dt)
      {:error, _} -> nil
    end
  end
end