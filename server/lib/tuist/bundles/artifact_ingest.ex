defmodule Tuist.Bundles.ArtifactIngest do
  @moduledoc """
  ClickHouse-shaped sibling of `Tuist.Bundles.Artifact`.

  Used during the PG → CH migration of the `artifacts` table. Until reads are
  cut over, `Tuist.Bundles.Artifact` remains the source of truth and this
  schema receives synchronous shadow writes from
  `Tuist.Bundles.create_bundle/2`. We deliberately do not use
  `Tuist.Ingestion.Bufferable` here: a buffered async flush that crashes on
  a transient ClickHouse outage would silently drop rows after the PG
  transaction has already committed, with no durable record for the
  follow-up backfill to recover. Going synchronous lets the write fail
  loudly (caught by the rescue in `Bundles`) and leaves the bundle's
  `artifacts_replicated_to_ch` flag unset so the backfill picks it up.

  Rows match the PG layout one-for-one except `size` is `Int64` (the column
  whose width was the original motivation for migrating off PG; see the
  reverted [#10477](https://github.com/tuist/tuist/pull/10477)).
  """

  use Ecto.Schema

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
