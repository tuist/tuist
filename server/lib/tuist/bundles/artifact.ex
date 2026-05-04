defmodule Tuist.Bundles.Artifact do
  @moduledoc """
  ClickHouse-backed schema for bundle artifacts.
  """

  use Ecto.Schema

  @artifact_types [:directory, :file, :font, :binary, :localization, :asset, :unknown]

  @primary_key {:id, Ch, type: "UUID", autogenerate: false}
  schema "artifacts" do
    field :bundle_id, Ch, type: "UUID"
    field :artifact_type, Ch, type: "LowCardinality(String)"
    field :path, Ch, type: "String"
    field :size, Ch, type: "Int64"
    field :shasum, Ch, type: "String"
    field :artifact_id, Ch, type: "Nullable(UUID)"

    field :inserted_at, Ch, type: "DateTime64(6)"
    field :updated_at, Ch, type: "DateTime64(6)"
  end

  @doc """
  Atom values accepted as `artifact_type` on bundle artifact uploads.
  """
  def artifact_types, do: @artifact_types

  @doc """
  Builds a CH-shaped row from the flattened artifact map produced by
  `Tuist.Bundles.flatten_artifacts/4`.
  """
  def to_ch_row(%{} = artifact) do
    %{
      id: Map.fetch!(artifact, :id),
      bundle_id: Map.fetch!(artifact, :bundle_id),
      artifact_type: artifact_type_to_string(Map.fetch!(artifact, :artifact_type)),
      path: Map.fetch!(artifact, :path),
      size: Map.fetch!(artifact, :size),
      shasum: Map.fetch!(artifact, :shasum),
      artifact_id: Map.get(artifact, :artifact_id),
      inserted_at: to_naive_usec(Map.fetch!(artifact, :inserted_at)),
      updated_at: to_naive_usec(Map.fetch!(artifact, :updated_at))
    }
  end

  defp artifact_type_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp artifact_type_to_string(value) when is_binary(value), do: value

  # PG `:utc_datetime` returns `%DateTime{microsecond: {0, 0}}`. The Ch
  # adapter maps `DateTime64(6)` to Ecto's `:naive_datetime_usec`, which
  # imposes two requirements that the PG value violates:
  #
  #   1. it rejects `DateTime` outright — must be `NaiveDateTime`
  #   2. it requires the microsecond precision element to be 6, not 0,
  #      via `Ecto.Type.check_usec!/2`
  #
  # So we strip the timezone (PG always stores UTC) and bump the precision.
  defp to_naive_usec(%DateTime{} = dt) do
    dt |> DateTime.to_naive() |> bump_usec_precision()
  end

  defp to_naive_usec(%NaiveDateTime{} = ndt), do: bump_usec_precision(ndt)

  defp bump_usec_precision(%NaiveDateTime{microsecond: {value, _}} = ndt) do
    %{ndt | microsecond: {value, 6}}
  end
end
