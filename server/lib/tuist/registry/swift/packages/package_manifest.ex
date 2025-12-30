defmodule Tuist.Registry.Swift.Packages.PackageManifest do
  @moduledoc """
  A module that represents a Swift package manifest (Package.swift).
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Registry.Swift.Packages.PackageRelease

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "package_manifests" do
    belongs_to :package_release, PackageRelease, type: UUIDv7
    field :swift_version, :string
    field :swift_tools_version, :string

    timestamps(type: :utc_datetime)
  end

  def create_changeset(token, attrs) do
    token
    |> cast(attrs, [
      :package_release_id,
      :swift_version,
      :swift_tools_version
    ])
    |> validate_required([:package_release_id])
    |> unique_constraint([:package_release_id, :swift_version])
  end
end
