defmodule Tuist.Registry.Swift.Packages.PackageRelease do
  @moduledoc """
  A module that represents a Swift package release.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Registry.Swift.Packages.Package

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "package_releases" do
    belongs_to :package, Package, type: UUIDv7
    has_many :manifests, Tuist.Registry.Swift.Packages.PackageManifest
    field :checksum, :string
    field :version, :string

    timestamps(type: :utc_datetime)
  end

  def create_changeset(token, attrs) do
    token
    |> cast(attrs, [
      :package_id,
      :checksum,
      :version
    ])
    |> validate_required([:package_id, :checksum, :version])
    |> unique_constraint([:package_id, :version])
  end
end
