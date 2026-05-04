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
end
