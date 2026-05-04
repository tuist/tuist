defmodule Tuist.Bundles.BundleIngest do
  @moduledoc """
  ClickHouse-shaped sibling of `Tuist.Bundles.Bundle`. Used to dual-write
  bundle rows to ClickHouse during the PG → CH migration. Will be folded
  back into `Tuist.Bundles.Bundle` once the cutover is complete and the
  PG `bundles` table is dropped.
  """

  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  alias Tuist.Bundles.Bundle

  @primary_key {:id, Ch, type: "UUID", autogenerate: false}
  schema "bundles" do
    field :app_bundle_id, Ch, type: "String"
    field :name, Ch, type: "String"
    field :install_size, Ch, type: "Int64"
    field :download_size, Ch, type: "Nullable(Int64)"
    field :git_branch, Ch, type: "Nullable(String)"
    field :git_commit_sha, Ch, type: "Nullable(String)"
    field :git_ref, Ch, type: "Nullable(String)"
    field :supported_platforms, Ch, type: "Array(LowCardinality(String))"
    field :version, Ch, type: "String"
    field :type, Ch, type: "LowCardinality(String)"
    field :project_id, Ch, type: "Int64"
    field :uploaded_by_account_id, Ch, type: "Nullable(Int64)"

    field :inserted_at, Ch, type: "DateTime64(6)"
    field :updated_at, Ch, type: "DateTime64(6)"
  end

  @doc """
  Builds a CH-shaped row map from a persisted `Tuist.Bundles.Bundle`.
  Atom-valued enum fields (`type`, `supported_platforms`) are encoded
  as strings to match the `LowCardinality(String)` column types.
  Timestamps are normalized to microsecond-precision `NaiveDateTime`
  for the `DateTime64(6)` columns.
  """
  def from_bundle(%Bundle{} = bundle) do
    %{
      id: bundle.id,
      app_bundle_id: bundle.app_bundle_id,
      name: bundle.name,
      install_size: bundle.install_size,
      download_size: bundle.download_size,
      git_branch: bundle.git_branch,
      git_commit_sha: bundle.git_commit_sha,
      git_ref: bundle.git_ref,
      supported_platforms: encode_platforms(bundle.supported_platforms),
      version: bundle.version,
      type: encode_type(bundle.type),
      project_id: bundle.project_id,
      uploaded_by_account_id: bundle.uploaded_by_account_id,
      inserted_at: to_naive_usec(bundle.inserted_at),
      updated_at: to_naive_usec(bundle.updated_at)
    }
  end

  defp encode_platforms(nil), do: []
  defp encode_platforms(platforms), do: Enum.map(platforms, &Atom.to_string/1)

  defp encode_type(type) when is_atom(type), do: Atom.to_string(type)
  defp encode_type(type) when is_binary(type), do: type

  defp to_naive_usec(%DateTime{} = dt) do
    dt |> DateTime.to_naive() |> bump_usec_precision()
  end

  defp to_naive_usec(%NaiveDateTime{} = ndt), do: bump_usec_precision(ndt)

  defp bump_usec_precision(%NaiveDateTime{microsecond: {value, _}} = ndt) do
    %{ndt | microsecond: {value, 6}}
  end
end
