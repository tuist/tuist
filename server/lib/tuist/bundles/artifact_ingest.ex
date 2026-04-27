defmodule Tuist.Bundles.ArtifactIngest do
  @moduledoc """
  ClickHouse-shaped sibling of `Tuist.Bundles.Artifact`.

  Used during the PG → CH migration of the `artifacts` table. Until reads are
  cut over, `Tuist.Bundles.Artifact` remains the source of truth and this
  schema only receives shadow writes via the `Bufferable`-generated
  `Tuist.Bundles.ArtifactIngest.Buffer` submodule.

  Rows match the PG layout one-for-one except `size` is `Int64` (the column
  whose width was the original motivation for migrating off PG; see the
  reverted [#10477](https://github.com/tuist/tuist/pull/10477)).
  """

  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  @primary_key {:id, Ch, type: "UUID", autogenerate: false}
  schema "artifacts" do
    field :bundle_id, Ch, type: "UUID"

    field :artifact_type, Ch,
      type: "Enum8('directory' = 0, 'file' = 1, 'font' = 2, 'binary' = 3, 'localization' = 4, 'asset' = 5, 'unknown' = 6)"

    field :path, Ch, type: "String"
    field :size, Ch, type: "Int64"
    field :shasum, Ch, type: "String"
    field :artifact_id, Ch, type: "Nullable(UUID)"

    field :inserted_at, Ch, type: "DateTime64(6)"
    field :updated_at, Ch, type: "DateTime64(6)"
  end

  @doc """
  Builds a CH-shaped row from a PG `Tuist.Bundles.Artifact` struct (or the
  pre-insert map produced by `Tuist.Bundles.flatten_artifacts/4`).
  """
  def from_pg(%{} = artifact) do
    %{
      id: Map.fetch!(artifact, :id),
      bundle_id: Map.fetch!(artifact, :bundle_id),
      artifact_type: artifact_type_to_string(Map.fetch!(artifact, :artifact_type)),
      path: Map.fetch!(artifact, :path),
      size: Map.fetch!(artifact, :size),
      shasum: Map.fetch!(artifact, :shasum),
      artifact_id: Map.get(artifact, :artifact_id),
      inserted_at: to_naive_us(Map.fetch!(artifact, :inserted_at)),
      updated_at: to_naive_us(Map.fetch!(artifact, :updated_at))
    }
  end

  defp artifact_type_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp artifact_type_to_string(value) when is_binary(value), do: value

  defp to_naive_us(%DateTime{} = dt) do
    dt |> DateTime.to_naive() |> Map.update!(:microsecond, fn {value, _} -> {value, 6} end)
  end

  defp to_naive_us(%NaiveDateTime{} = ndt) do
    Map.update!(ndt, :microsecond, fn {value, _} -> {value, 6} end)
  end
end
